`timescale 1ns/1ps

// Self-checking testbench for pc.v
// Inputs change on the falling edge, values are checked one edge later.

module tb_pc;

    reg        clk = 0;
    reg        rst;
    reg        pc_load, pc_inc;
    reg  [7:0] pc_in;
    wire [7:0] pc_out;

    integer pass_count = 0;
    integer fail_count = 0;

    pc dut (
        .clk     (clk),
        .rst     (rst),
        .pc_load (pc_load),
        .pc_inc  (pc_inc),
        .pc_in   (pc_in),
        .pc_out  (pc_out)
    );

    always #5 clk = ~clk;

    // set the control inputs and let one rising edge happen
    task step;
        input       t_load;
        input       t_inc;
        input [7:0] t_in;
        begin
            pc_load = t_load;
            pc_inc  = t_inc;
            pc_in   = t_in;
            @(negedge clk);
        end
    endtask

    task check;
        input [7:0]      expected;
        input [8*28-1:0] name;
        begin
            if (pc_out === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : pc=%h", name, pc_out);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : pc=%h (exp %h)", name, pc_out, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_pc.vcd");
        $dumpvars(0, tb_pc);

        rst = 1; pc_load = 0; pc_inc = 0; pc_in = 0;
        @(negedge clk);
        @(negedge clk);
        check(8'h00, "reset -> 00");
        rst = 0;

        step(0, 0, 8'h55);  check(8'h00, "hold (no load, no inc)");
        step(0, 0, 8'h55);  check(8'h00, "hold again");

        step(0, 1, 8'h00);  check(8'h01, "inc -> 01");
        step(0, 1, 8'h00);  check(8'h02, "inc -> 02");
        step(0, 1, 8'h00);  check(8'h03, "inc -> 03");

        step(1, 0, 8'hF0);  check(8'hF0, "load F0");
        step(0, 1, 8'h00);  check(8'hF1, "inc after load -> F1");

        step(1, 0, 8'hFE);  check(8'hFE, "load FE");
        step(0, 1, 8'h00);  check(8'hFF, "inc -> FF");
        step(0, 1, 8'h00);  check(8'h00, "inc wraps FF -> 00");

        step(1, 1, 8'h40);  check(8'h40, "load beats inc");
        step(0, 0, 8'h00);  check(8'h40, "hold after load");

        // reset wins over inc
        rst = 1;
        step(0, 1, 8'h00);  check(8'h00, "reset beats inc");
        rst = 0;
        step(0, 1, 8'h00);  check(8'h01, "inc after reset -> 01");

        $display("------------------------------------------");
        $display("SUMMARY tb_pc: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
