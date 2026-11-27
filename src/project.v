/*
    project.v
*/
`default_nettype none

module tt_um_mouadasm_tinytapeout_project (
    input  wire [7:0] ui_in,    
    output wire [7:0] uo_out,   
    input  wire [7:0] uio_in,   
    output wire [7:0] uio_out,  
    output wire [7:0] uio_oe,   
    input  wire ena,     
    input  wire clk,      
    input  wire rst_n    
);

    localparam num_cells = 2;  // IPSPs in the row (bandwidth of A)
    localparam operand_width = 8;
    localparam accumulator_width = 18;
    localparam [2:0] b_phase = num_cells[2:0];

    
    reg pause_r;
    always @(posedge clk) begin
        if (!rst_n) pause_r <= 1'b0;
        else        pause_r <= uio_in[4];
    end
    wire en = ena & ~pause_r;

    
    reg [2:0] phase;
    always @(posedge clk) begin
        if (!rst_n)  phase <= 3'd0;
        else if (en) phase <= phase + 3'd1;
    end

    // holding registers: operands for the next step, collected one byte per cycle
    reg [num_cells*operand_width-1:0] hold_a;
    reg [operand_width-1:0] hold_b;
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


    wire signed [accumulator_width-1:0] y;        
    wire signed [accumulator_width-1:0] c_link;  
    wire signed [operand_width-1:0] b_link;   
    wire signed [operand_width-1:0]  b_unused; 

    ipsp_serial u_ipsp0 (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a_in  (hold_a[0 +: operand_width]),
        .b_in  (hold_b),
        .c_in  (c_link),
        .b_out (b_link),
        .c_out (y)
    );

    ipsp_serial u_ipsp1 (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a_in  (hold_a[operand_width +: operand_width]),
        .b_in  (b_link),
        .c_in  ({accumulator_width{1'b0}}), // sums start at 0 on the right
        .b_out (b_unused),
        .c_out (c_link)
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
