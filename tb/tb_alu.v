`timescale 1ns/1ps

// Self-checking testbench for alu.v
// Flags are written as {Z, C, N, V}, e.g. 4'b0011 means N=1, V=1.

module tb_alu;

    reg  [3:0] alu_op;
    reg  [7:0] a, b;
    reg  [3:0] flags_in;
    wire [7:0] result;
    wire [3:0] flags_out;

    integer pass_count = 0;
    integer fail_count = 0;

    alu dut (
        .alu_op    (alu_op),
        .a         (a),
        .b         (b),
        .flags_in  (flags_in),
        .result    (result),
        .flags_out (flags_out)
    );

    // apply inputs, wait, compare result and flags
    task check;
        input [3:0]      t_op;
        input [7:0]      t_a;
        input [7:0]      t_b;
        input [3:0]      t_fin;
        input [7:0]      exp_r;
        input [3:0]      exp_f;
        input [8*28-1:0] name;
        begin
            alu_op   = t_op;
            a        = t_a;
            b        = t_b;
            flags_in = t_fin;
            #10;
            if (result === exp_r && flags_out === exp_f) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : result=%h ZCNV=%b", name, result, flags_out);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : result=%h (exp %h) ZCNV=%b (exp %b)",
                         name, result, exp_r, flags_out, exp_f);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_alu.vcd");
        $dumpvars(0, tb_alu);

        //     op     a      b      fin      exp_r  exp_f    name
        // ADD
        check(4'h3, 8'h03, 8'h04, 4'b0000, 8'h07, 4'b0000, "ADD 3+4");
        check(4'h3, 8'h00, 8'h00, 4'b0000, 8'h00, 4'b1000, "ADD 0+0 (zero)");
        check(4'h3, 8'h7F, 8'h01, 4'b0000, 8'h80, 4'b0011, "ADD 127+1 (overflow)");
        check(4'h3, 8'hFF, 8'h01, 4'b0000, 8'h00, 4'b1100, "ADD 255+1 (carry, zero)");
        check(4'h3, 8'h80, 8'h80, 4'b0000, 8'h00, 4'b1101, "ADD -128+-128 (C,V,Z)");
        check(4'h3, 8'hFF, 8'hFF, 4'b0000, 8'hFE, 4'b0110, "ADD -1+-1 (C,N)");

        // SUB (C = borrow)
        check(4'h4, 8'h05, 8'h03, 4'b0000, 8'h02, 4'b0000, "SUB 5-3");
        check(4'h4, 8'h07, 8'h07, 4'b0000, 8'h00, 4'b1000, "SUB 7-7 (zero)");
        check(4'h4, 8'h00, 8'h01, 4'b0000, 8'hFF, 4'b0110, "SUB 0-1 (borrow, neg)");
        check(4'h4, 8'h80, 8'h01, 4'b0000, 8'h7F, 4'b0001, "SUB -128-1 (overflow)");
        check(4'h4, 8'h7F, 8'hFF, 4'b0000, 8'h80, 4'b0111, "SUB 127-(-1) (C,N,V)");

        // logic ops: only Z and N change, C and V come from flags_in
        check(4'h5, 8'hF0, 8'h3C, 4'b0101, 8'h30, 4'b0101, "AND keeps C,V");
        check(4'h5, 8'hF0, 8'h0F, 4'b0000, 8'h00, 4'b1000, "AND zero");
        check(4'h6, 8'h80, 8'h01, 4'b0000, 8'h81, 4'b0010, "OR negative");
        check(4'h6, 8'h00, 8'h00, 4'b0010, 8'h00, 4'b1000, "OR zero, clears N");
        check(4'h7, 8'hAA, 8'hAA, 4'b0100, 8'h00, 4'b1100, "XOR self = 0 keeps C");
        check(4'h7, 8'hAA, 8'h0F, 4'b0000, 8'hA5, 4'b0010, "XOR negative");
        check(4'h8, 8'h00, 8'h55, 4'b0000, 8'hFF, 4'b0010, "NOT 0x00 (ignores b)");
        check(4'h8, 8'hFF, 8'h00, 4'b0001, 8'h00, 4'b1001, "NOT 0xFF keeps V");

        // shifts: Z, C, N change, V kept
        check(4'h9, 8'h81, 8'h00, 4'b0000, 8'h02, 4'b0100, "SHL 0x81 (carry out)");
        check(4'h9, 8'h40, 8'h00, 4'b0000, 8'h80, 4'b0010, "SHL 0x40 (negative)");
        check(4'h9, 8'h80, 8'h00, 4'b0000, 8'h00, 4'b1100, "SHL 0x80 (C, Z)");
        check(4'h9, 8'h01, 8'h00, 4'b0101, 8'h02, 4'b0001, "SHL clears C, keeps V");
        check(4'hA, 8'h01, 8'h00, 4'b0000, 8'h00, 4'b1100, "SHR 0x01 (C, Z)");
        check(4'hA, 8'h80, 8'h00, 4'b0010, 8'h40, 4'b0000, "SHR 0x80 (logical)");
        check(4'hA, 8'hFF, 8'h00, 4'b0000, 8'h7F, 4'b0100, "SHR 0xFF (carry out)");

        // non-ALU opcodes: result = b, flags unchanged
        check(4'h0, 8'h12, 8'h34, 4'b0111, 8'h34, 4'b0111, "NOP keeps flags");
        check(4'h1, 8'h12, 8'h00, 4'b1010, 8'h00, 4'b1010, "MOV pass b, keeps flags");
        check(4'h2, 8'h12, 8'h9C, 4'b0000, 8'h9C, 4'b0000, "LDI pass imm, no N");
        check(4'hB, 8'h12, 8'h56, 4'b1111, 8'h56, 4'b1111, "LD keeps flags");

        $display("------------------------------------------");
        $display("SUMMARY tb_alu: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
