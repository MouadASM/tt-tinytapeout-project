/*
    project.v
    Tiny Tapeout top level: a linear systolic row of shift-and-add IPSPs plus the controller
    that moves operands and results through the 8-bit Tiny Tapeout pins.

    One systolic step = 8 clock cycles (the IPSPs process one bit of b per cycle).
    The step phase (0..7) is shown on uio_out[3:1], and uio_out[0] = 1 on phase 0.

    Inputs: during step s, the host writes the operands for step s+1 on ui_in:
        phase k (k = 0 .. num_cells-1): a for IPSP k
        phase num_cells:                b (the vector element for IPSP 0)
    They are held in registers and handed to the IPSPs on the next load cycle (phase 0).

    Outputs: the result y(s) of step s (c_out of IPSP 0, 18 bits) is captured at the start of
    step s+1 and sent on uo_out during step s+1:
        phase 1: y[7:0]   phase 2: y[15:8]   phase 3: y[17:16], sign-extended to 8 bits

    uio_in[4] = 1 pauses the whole design (all IPSPs and the controller).
*/
`default_nettype none

module tt_um_mouadasm_tinytapeout_project (
    input  wire [7:0] ui_in,    // dedicated inputs: operand bytes
    output wire [7:0] uo_out,   // dedicated outputs: result bytes
    input  wire [7:0] uio_in,   // IOs: input path  (bit 4 = pause)
    output wire [7:0] uio_out,  // IOs: output path (bit 0 = step start, bits 3:1 = phase)
    output wire [7:0] uio_oe,   // IOs: enable path (1 = output)
    input  wire       ena,      // 1 when this design is selected
    input  wire       clk,      // clock
    input  wire       rst_n     // active-low reset
);

    localparam num_cells         = 2;  // IPSPs in the row (bandwidth of A)
    localparam operand_width     = 8;
    localparam accumulator_width = 18;
    localparam [2:0] b_phase     = num_cells[2:0]; // phase on which b is written

    // pause input, registered once so the IPSPs' clock gate sees a clean, clock-aligned signal
    reg pause_r;
    always @(posedge clk) begin
        if (!rst_n) pause_r <= 1'b0;
        else        pause_r <= uio_in[4];
    end
    wire en = ena & ~pause_r;

    // step phase: counts 0..7 in lockstep with the IPSPs' own counters
    // (both are reset together and both advance only when en = 1)
    reg [2:0] phase;
    always @(posedge clk) begin
        if (!rst_n)  phase <= 3'd0;
        else if (en) phase <= phase + 3'd1;
    end

    // holding registers: operands for the next step, collected one byte per cycle
    reg [num_cells*operand_width-1:0] hold_a;
    reg [operand_width-1:0]           hold_b;
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            hold_a <= {num_cells*operand_width{1'b0}};
            hold_b <= {operand_width{1'b0}};
        end else if (en) begin
            for (k = 0; k < num_cells; k = k + 1)
                if (phase == k[2:0]) hold_a[k*operand_width +: operand_width] <= ui_in;
            if (phase == b_phase) hold_b <= ui_in;
        end
    end

    // the systolic row
    wire signed [accumulator_width-1:0] y;
    wire signed [operand_width-1:0]     b_unused;

    systolic_row #(
        .num_cells         (num_cells),
        .operand_width     (operand_width),
        .accumulator_width (accumulator_width)
    ) u_row (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a_in  (hold_a),
        .b_in  (hold_b),
        .c_in  ({accumulator_width{1'b0}}), // sums start at 0 on the right
        .b_out (b_unused),
        .c_out (y)
    );

    // capture the finished result on the load cycle (phase 0), before the IPSPs overwrite it
    reg [accumulator_width-1:0] y_hold;
    always @(posedge clk) begin
        if (!rst_n)                   y_hold <= {accumulator_width{1'b0}};
        else if (en && phase == 3'd0) y_hold <= y;
    end

    // send the result one byte per cycle
    assign uo_out = (phase == 3'd1) ? y_hold[7:0]  :
                    (phase == 3'd2) ? y_hold[15:8] :
                    (phase == 3'd3) ? {{6{y_hold[17]}}, y_hold[17:16]} : 8'd0;

    assign uio_out = {4'b0000, phase, (phase == 3'd0)};
    assign uio_oe  = 8'b0000_1111;

    // unused inputs
    wire _unused = &{uio_in[7:5], uio_in[3:0], b_unused, 1'b0};

endmodule

`default_nettype wire
