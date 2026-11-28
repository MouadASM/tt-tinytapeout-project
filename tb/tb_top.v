
`timescale 1ns/1ps
`default_nettype none

module tb_top;

    localparam N = 2;    
    localparam M = 6;    
    localparam S_MAT = 2*M + 2;
    localparam S_MAX = S_MAT + 300;

    reg  clk = 1'b0, rst_n = 1'b0, ena = 1'b1;
    reg  [7:0] ui_in = 8'd0, uio_in = 8'd0;
    wire [7:0] uo_out, uio_out, uio_oe;

    tt_um_mo_systolic dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out),
        .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk; // 50 MHz

    integer a_op [0:(S_MAX+1)*N-1];
    integer b_op [0:S_MAX+1];
    integer A    [0:M*N-1];  
    integer x    [0:M-1];
    integer y_seen [0:S_MAX];

    integer s, k, m, step, prev_phase, phase, errors, checks, pauses;
    reg [7:0] byte1, byte2, byte3;
    reg [17:0] y_bits;
    integer y_val, expect_val;

    function integer model_y(input integer t);  
        integer j, acc;
        begin
            acc = 0;
            for (j = 0; j < N; j = j + 1)
                if (t - 2*j >= 0) acc = acc + a_op[(t-j)*N + j] * b_op[t - 2*j];
            model_y = acc;
        end
    endfunction

    function integer to_signed18(input [17:0] v);
        begin
            to_signed18 = v[17] ? $signed({14'h3FFF, v}) : $signed({14'h0, v});
        end
    endfunction

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        errors = 0; checks = 0; pauses = 0;

       
        for (s = 0; s <= S_MAX + 1; s = s + 1) begin
            b_op[s] = 0;
            for (k = 0; k < N; k = k + 1) a_op[s*N + k] = 0;
        end
   
        for (m = 0; m < M; m = m + 1) begin
            x[m] = ($random % 16);
            for (k = 0; k < N; k = k + 1)
                A[m*N + k] = (m - k >= 0) ? ($random % 16) : 0;
        end
    
        for (m = 0; m < M; m = m + 1) begin
            b_op[2*m + 2] = x[m];
            for (k = 0; k < N; k = k + 1)
                a_op[(2*m + 2 - k)*N + k] = A[m*N + k];
        end
        
        for (s = S_MAT + 1; s <= S_MAX; s = s + 1) begin
            b_op[s] = ($random % 128);
            if ($random % 8 == 0) b_op[s] = -128;
            for (k = 0; k < N; k = k + 1) begin
                a_op[s*N + k] = ($random % 128);
                if ($random % 8 == 0) a_op[s*N + k] = -128;
            end
        end

    
        rst_n = 0; repeat (3) @(posedge clk); @(negedge clk); rst_n = 1;

    
        step = 0; prev_phase = 0;
        while (step <= S_MAX) begin
            phase = uio_out[3:1];
            if (phase == 0 && prev_phase == 7) step = step + 1;

            // operands for the next step
            if (phase < N)       ui_in = a_op[(step + 1)*N + phase];
            else if (phase == N) ui_in = b_op[step + 1];
            else                 ui_in = 8'd0;

            // result of the previous step
            if (phase == 1) byte1 = uo_out;
            if (phase == 2) byte2 = uo_out;
            if (phase == 3) byte3 = uo_out;
            if (phase == 4 && prev_phase == 3 && step >= 1) begin
                y_bits = {byte3[1:0], byte2, byte1};
                y_val  = to_signed18(y_bits);
                y_seen[step - 1] = y_val;
                if (step - 1 >= N) begin
                    expect_val = to_signed18(model_y(step - 1));
                    checks = checks + 1;
                    if (y_val !== expect_val || byte3[7:2] !== {6{byte3[1]}}) begin
                        errors = errors + 1;
                        $display("FAIL step %0d: y = %0d, expected %0d", step - 1, y_val, expect_val);
                    end
                end
            end

            // random pauses in part 2
            if (step > S_MAT + 2 && $random % 40 == 0) begin
                uio_in[4] = 1'b1; pauses = pauses + 1;
            end else if ($random % 3 == 0) begin
                uio_in[4] = 1'b0;
            end
            if (step >= S_MAX - 2) uio_in[4] = 1'b0;

            prev_phase = phase;
            @(negedge clk);
        end

    
        $display("------------------------------------------");
        $display("Part 1: y = A x with a %0dx%0d matrix of bandwidth %0d", M, M, N);
        for (m = 0; m < M; m = m + 1) begin
            expect_val = 0;
            for (k = 0; k < N; k = k + 1)
                if (m - k >= 0) expect_val = expect_val + A[m*N + k] * x[m - k];
            checks = checks + 1;
            if (y_seen[2*m + 2] !== expect_val) begin
                errors = errors + 1;
                $display("  y[%0d] = %0d  expected %0d  FAIL", m, y_seen[2*m + 2], expect_val);
            end else
                $display("  y[%0d] = %0d  (A x = %0d)  ok", m, y_seen[2*m + 2], expect_val);
        end
        $display("Part 2: %0d random steps, %0d pauses", S_MAX - S_MAT, pauses);
        $display("------------------------------------------");
        $display("%0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule

`default_nettype wire