/*


*/
`default_nettype none

module ipsp #(
    parameter default_width= 8, // default operand 
    parameter accumulator_width=18, // default accumulator width in bits
) (
    input wire clk,
    input wire rst_n, //active-low reset
    input wire en,
    input wire signed [default_width-1:0] a_in,
    

);

    reg signed
