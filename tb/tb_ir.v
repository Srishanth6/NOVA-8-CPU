`timescale 1ns/1ps

// Self-checking testbench for ir.v
// Checks the stored value and the decoded fields.

module tb_ir;

    reg         clk = 0;
    reg         rst;
    reg         ir_load;
    reg  [15:0] ir_in;
    wire [15:0] ir_out;
    wire [3:0]  opcode;
    wire [1:0]  rd, rs;
    wire [7:0]  imm8;

    integer pass_count = 0;
    integer fail_count = 0;

    ir dut (
        .clk     (clk),
        .rst     (rst),
        .ir_load (ir_load),
        .ir_in   (ir_in),
        .ir_out  (ir_out),
        .opcode  (opcode),
        .rd      (rd),
        .rs      (rs),
        .imm8    (imm8)
    );

    always #5 clk = ~clk;

    task step;
        input        t_load;
        input [15:0] t_in;
        begin
            ir_load = t_load;
            ir_in   = t_in;
            @(negedge clk);
        end
    endtask

    task check;
        input [15:0]     exp_ir;
        input [3:0]      exp_op;
        input [1:0]      exp_rd;
        input [1:0]      exp_rs;
        input [7:0]      exp_imm;
        input [8*28-1:0] name;
        begin
            if (ir_out === exp_ir && opcode === exp_op && rd === exp_rd &&
                rs === exp_rs && imm8 === exp_imm) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : ir=%h op=%h rd=%0d rs=%0d imm=%h",
                         name, ir_out, opcode, rd, rs, imm8);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : ir=%h op=%h rd=%0d rs=%0d imm=%h (exp %h %h %0d %0d %h)",
                         name, ir_out, opcode, rd, rs, imm8,
                         exp_ir, exp_op, exp_rd, exp_rs, exp_imm);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_ir.vcd");
        $dumpvars(0, tb_ir);

        rst = 1; ir_load = 0; ir_in = 16'h0000;
        @(negedge clk);
        @(negedge clk);
        check(16'h0000, 4'h0, 2'd0, 2'd0, 8'h00, "reset -> 0000 (NOP)");
        rst = 0;

        // 0x3655 = ADD R1, R2 (imm 55 just to see the field)
        step(1, 16'h3655);
        check(16'h3655, 4'h3, 2'd1, 2'd2, 8'h55, "load 3655 fields");

        step(0, 16'hFFFF);
        check(16'h3655, 4'h3, 2'd1, 2'd2, 8'h55, "ir_load=0 holds");

        // 0xEFAB = opcode E, rd 3, rs 3, imm AB
        step(1, 16'hEFAB);
        check(16'hEFAB, 4'hE, 2'd3, 2'd3, 8'hAB, "load EFAB fields");

        // 0xC810 = ST R2, 0x10
        step(1, 16'hC810);
        check(16'hC810, 4'hC, 2'd2, 2'd0, 8'h10, "load C810 fields");

        rst = 1;
        step(1, 16'h1234);
        check(16'h0000, 4'h0, 2'd0, 2'd0, 8'h00, "reset beats load");
        rst = 0;

        $display("------------------------------------------");
        $display("SUMMARY tb_ir: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
