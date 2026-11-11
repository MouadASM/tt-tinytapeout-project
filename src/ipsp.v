/*
    ipsp.v 
    This is the Inner Product Step Processor (IPSP) in my linear systolic array
*/
`default_nettype none

module ipsp #(
    parameter operand_width= 8, // default operand 
    parameter accumulator_width=18 // default accumulator width in bits
) (
    input wire clk,
    input wire rst_n, //active-low reset
    input wire en,

    // inputs
    input wire signed [operand_width-1:0] a_in, // matrix element from above
    input wire signed [operand_width-1:0] b_in, // vector element from the left
    input wire signed [accumulator_width-1:0] c_in, // partial sum from preceding right IPSP


    // outputs
    output wire signed [operand_width-1:0] b_out, // to the right IPSP neighbour
    output wire signed [accumulator_width-1:0] c_out // to the left IPSP neighbour
    

);

    // IPSP registers
    reg signed [operand_width-1:0] r_a; // register a in the IPSP
    reg signed [operand_width-1:0] r_b; // register b
    reg signed [accumulator_width-1:0] r_c; //register c

    always @(posedge clk) begin
        if (!rst_n) begin
            r_a<= {operand_width{1'b0}};
            r_b<= {operand_width{1'b0}};
            r_c<= {accumulator_width{1'b0}};
        end else if (en) begin
            r_a<= a_in;
            r_b<=b_in;
            r_c <=c_in;
        end
    end

    // 2W-bit signed product, sign-extended into the accumulator width.
    wire signed [2*operand_width-1:0] product= r_a * r_b;


    // redundant b out
    assign b_out = r_b;
    assign c_out = r_c + {{(accumulator_width-2*operand_width){product[2*operand_width-1]}}, product};

endmodule

`default_nettype wire




