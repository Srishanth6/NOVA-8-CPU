`timescale 1ns/1ps

// Self-checking testbench for reg_file.v
// Inputs change on the falling edge so they are stable at the rising edge.

module tb_reg_file;

    reg        clk = 0;
    reg        rst;
    reg        w_en;
    reg  [1:0] w_addr;
    reg  [7:0] w_data;
    reg  [1:0] addr_a, addr_b;
    wire [7:0] data_a, data_b;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    reg_file dut (
        .clk    (clk),
        .rst    (rst),
        .w_en   (w_en),
        .w_addr (w_addr),
        .w_data (w_data),
        .addr_a (addr_a),
        .data_a (data_a),
        .addr_b (addr_b),
        .data_b (data_b)
    );

    always #5 clk = ~clk;  // 100 MHz

    // write one register over one clock edge
    task write_reg;
        input [1:0] addr;
        input [7:0] data;
        begin
            @(negedge clk);
            w_en   = 1'b1;
            w_addr = addr;
            w_data = data;
            @(negedge clk);
            w_en   = 1'b0;
        end
    endtask

    // read both ports and compare
    task check_read;
        input [1:0]      ra;
        input [7:0]      exp_a;
        input [1:0]      rb;
        input [7:0]      exp_b;
        input [8*28-1:0] name;
        begin
            addr_a = ra;
            addr_b = rb;
            #1;
            if (data_a === exp_a && data_b === exp_b) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : R%0d=%h R%0d=%h", name, ra, data_a, rb, data_b);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : R%0d=%h (exp %h) R%0d=%h (exp %h)",
                         name, ra, data_a, exp_a, rb, data_b, exp_b);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);

        rst = 1; w_en = 0; w_addr = 0; w_data = 0; addr_a = 0; addr_b = 0;
        @(negedge clk);
        @(negedge clk);
        rst = 0;

        // 1. reset clears everything
        check_read(2'd0, 8'h00, 2'd1, 8'h00, "reset R0,R1 = 0");
        check_read(2'd2, 8'h00, 2'd3, 8'h00, "reset R2,R3 = 0");

        // 2. write each register with a different value
        write_reg(2'd0, 8'hA5);
        write_reg(2'd1, 8'h3C);
        write_reg(2'd2, 8'hFF);
        write_reg(2'd3, 8'h01);

        // 3. read on both ports, in both orders
        check_read(2'd0, 8'hA5, 2'd1, 8'h3C, "read R0 on A, R1 on B");
        check_read(2'd2, 8'hFF, 2'd3, 8'h01, "read R2 on A, R3 on B");
        check_read(2'd3, 8'h01, 2'd0, 8'hA5, "read R3 on A, R0 on B");
        check_read(2'd1, 8'h3C, 2'd2, 8'hFF, "read R1 on A, R2 on B");

        // 4. same register on both ports
        for (i = 0; i < 4; i = i + 1) begin
            addr_a = i;
            addr_b = i;
            #1;
            if (data_a === data_b) begin
                pass_count = pass_count + 1;
                $display("PASS  both ports read R%0d : %h", i, data_a);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  both ports read R%0d : A=%h B=%h", i, data_a, data_b);
            end
        end

        // 5. w_en = 0 must not write
        @(negedge clk);
        w_en = 1'b0; w_addr = 2'd1; w_data = 8'h99;
        @(negedge clk);
        check_read(2'd1, 8'h3C, 2'd0, 8'hA5, "w_en=0 does not write R1");

        // 6. overwrite R2, the others stay the same
        write_reg(2'd2, 8'h00);
        check_read(2'd2, 8'h00, 2'd3, 8'h01, "overwrite R2, R3 unchanged");
        check_read(2'd0, 8'hA5, 2'd1, 8'h3C, "overwrite R2, R0,R1 same");

        // 7. write is synchronous: old value before the edge, new value after
        @(negedge clk);
        w_en = 1'b1; w_addr = 2'd3; w_data = 8'h7E;
        check_read(2'd3, 8'h01, 2'd3, 8'h01, "before edge R3 still old");
        @(negedge clk);
        w_en = 1'b0;
        check_read(2'd3, 8'h7E, 2'd3, 8'h7E, "after edge R3 updated");

        // 8. reset again clears everything
        @(negedge clk);
        rst = 1;
        @(negedge clk);
        rst = 0;
        check_read(2'd0, 8'h00, 2'd1, 8'h00, "re-reset R0,R1 = 0");
        check_read(2'd2, 8'h00, 2'd3, 8'h00, "re-reset R2,R3 = 0");

        // 9. reset wins over a write in the same cycle
        @(negedge clk);
        rst = 1; w_en = 1'b1; w_addr = 2'd0; w_data = 8'h55;
        @(negedge clk);
        rst = 0; w_en = 1'b0;
        check_read(2'd0, 8'h00, 2'd0, 8'h00, "reset beats write to R0");

        $display("------------------------------------------");
        $display("SUMMARY tb_reg_file: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
