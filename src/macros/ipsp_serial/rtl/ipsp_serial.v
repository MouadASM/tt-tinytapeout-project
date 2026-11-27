/*
    ipsp_serial_cg.v (module name stays ipsp_serial)
    Inner Product Step Processor (IPSP) with a shift-and-add multiplier.
    One systolic step takes operand_width clock cycles:
      - load cycle (count = 0): capture a, b and c, and add the first partial product
      - cycles 1 .. operand_width-1: add one more partial product per cycle
    The top bit of b has negative weight (two's complement), so the last cycle subtracts.
    Area optimisations:
      - only the step counter is reset; the datapath registers are overwritten on every load cycle
      - b is rotated so the bit needed is always r_b[0] (no bit-select multiplexer)
    Clock-gated version: one clock-gating cell pauses the datapath instead of an
    enable multiplexer on every flip-flop.
*/
`default_nettype none

module ipsp_serial #(
    parameter operand_width     = 8, // bits per operand (W)
    parameter num_cells         = 4, // IPSPs in the row, only used to size the accumulator
    parameter accumulator_width = 2*operand_width + $clog2(num_cells) // fits num_cells products
) (
    input wire clk,
    input wire rst_n, // active-low reset
    input wire en,    // 0 = freeze everything (including the step counter)

    // inputs (only sampled on the load cycle)
    input wire signed [operand_width-1:0]     a_in, // matrix element from above
    input wire signed [operand_width-1:0]     b_in, // vector element from the left
    input wire signed [accumulator_width-1:0] c_in, // partial sum from the right-hand IPSP

    // outputs
    output wire signed [operand_width-1:0]     b_out, // to the right-hand IPSP
    output wire signed [accumulator_width-1:0] c_out  // to the left-hand IPSP (valid at the end of a step)
);

    localparam product_width = 2*operand_width;      // a * b needs 2W bits
    localparam count_width   = $clog2(operand_width); // counts 0 .. W-1
    localparam last_bit      = operand_width - 1;
    localparam [count_width-1:0] last_count = last_bit[count_width-1:0]; // last bit index, at counter width

    // IPSP registers
    reg signed [operand_width-1:0]     r_b;       // b, rotated once per cycle; equals b again at the end of the step
    reg signed [accumulator_width-1:0] r_c;       // running total: starts at c_in, collects the partial products
    reg signed [product_width-1:0]     r_a_shift; // a, doubled (shifted left) every cycle
    reg        [count_width-1:0]       count;     // which bit of b we are on

    wire load = (count == 0); // first cycle of a step

    // a sign-extended to 2W bits, ready to be shifted
    wire signed [product_width-1:0] a_ext = {{operand_width{a_in[last_bit]}}, a_in};

    // the partial product for this cycle: a (or a shifted) if the bit of b is 1, otherwise 0
    wire                            b_bit      = load ? b_in[0] : r_b[0];
    wire signed [product_width-1:0] a_now      = load ? a_ext   : r_a_shift;
    wire signed [product_width-1:0] partial    = b_bit ? a_now : {product_width{1'b0}};

    // sign-extend the partial product into the accumulator width
    wire signed [accumulator_width-1:0] partial_ext =
        {{(accumulator_width-product_width){partial[product_width-1]}}, partial};

    // the one adder, reused every cycle; subtract on the last bit (negative weight)
    wire signed [accumulator_width-1:0] c_start = load ? c_in : r_c;
    wire signed [accumulator_width-1:0] c_next  = (count == last_count) ? c_start - partial_ext
                                                                       : c_start + partial_ext;

    // clock gating: one gating cell replaces an enable multiplexer on every datapath flip-flop.
    // gated_clk only ticks when en = 1. The cell latches en while clk is low, so gated_clk never glitches.
    wire gated_clk;
`ifdef SYNTHESIS
    sky130_fd_sc_hd__dlclkp_1 u_clock_gate (.CLK(clk), .GATE(en), .GCLK(gated_clk));
`else
    reg en_latched; // simulation model of the same cell
    /* verilator lint_off LATCH */
    always @(clk or en) if (!clk) en_latched = en; // transparent while clk is low
    /* verilator lint_on LATCH */
    assign gated_clk = clk & en_latched;
`endif

    // the step counter keeps the normal clock so that reset works even while paused
    always @(posedge clk) begin
        if (!rst_n)
            count <= {count_width{1'b0}};
        else if (en)
            count <= (count == last_count) ? {count_width{1'b0}} : count + 1'b1;
    end

    // datapath: no reset and no enable needed (overwritten on every load cycle, frozen by the clock gate)
    always @(posedge gated_clk) begin
        r_b       <= load ? {b_in[0], b_in[operand_width-1:1]} : {r_b[0], r_b[operand_width-1:1]};
        r_c       <= c_next;
        r_a_shift <= {a_now[product_width-2:0], 1'b0};
    end

    assign b_out = r_b;
    assign c_out = r_c; // registered: no multiplier on the path to the neighbour

endmodule

`default_nettype wire
