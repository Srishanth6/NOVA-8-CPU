`timescale 1ns/1ps

// Gate-level simulation for NOVA-8
//
// Runs the RTL nova8_top and the Yosys gate netlist nova8_gate
// (sim/nova8_gate_<prog>.v, made from synth/gls.ys) side by side on the
// same clock and reset until both halt, and compares their outputs on every
// cycle: halted, pc_out, ram_we, and ram_addr / ram_wdata when ram_we = 1.
// !== is used everywhere, so an X on one side counts as a mismatch.
//
// Both CPUs run PROG. run.ps1 gls / make gls copy the program to
// sim/gls_prog.hex before synthesis, so the default matches the netlist.
// The netlist's RAM flip-flops have no reset, like the RTL RAM, so both
// start as X; the test programs never read RAM before writing it.

module tb_gls;

    parameter PROG = "sim/gls_prog.hex";

    localparam MAX_CYCLES = 5000;
    localparam MAX_SHOW   = 5;      // mismatching cycles printed in detail

    reg        clk = 0;
    reg        rst;

    wire       rtl_halted, gate_halted;
    wire [7:0] rtl_pc, gate_pc;
    wire       rtl_we, gate_we;
    wire [7:0] rtl_addr, gate_addr;
    wire [7:0] rtl_wdata, gate_wdata;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycles, compared, mismatches, first_bad;
    integer rtl_writes, gate_writes;

    nova8_top #(.PROG_FILE(PROG)) rtl (
        .clk       (clk),
        .rst       (rst),
        .halted    (rtl_halted),
        .pc_out    (rtl_pc),
        .ram_we    (rtl_we),
        .ram_addr  (rtl_addr),
        .ram_wdata (rtl_wdata)
    );

    nova8_gate gate (
        .clk       (clk),
        .rst       (rst),
        .halted    (gate_halted),
        .pc_out    (gate_pc),
        .ram_we    (gate_we),
        .ram_addr  (gate_addr),
        .ram_wdata (gate_wdata)
    );

    always #5 clk = ~clk;

    // compare the two CPUs once, called just after a falling edge
    task compare;
        reg bad;
        begin
            bad = (rtl_halted !== gate_halted) || (rtl_pc !== gate_pc) ||
                  (rtl_we !== gate_we) ||
                  (rtl_we === 1'b1 && (rtl_addr !== gate_addr || rtl_wdata !== gate_wdata));
            compared = compared + 1;
            if (bad) begin
                mismatches = mismatches + 1;
                if (first_bad < 0)
                    first_bad = cycles;
                if (mismatches <= MAX_SHOW)
                    $display("        cycle %0d: rtl halted=%b pc=%h we=%b addr=%h wdata=%h | gate halted=%b pc=%h we=%b addr=%h wdata=%h",
                             cycles, rtl_halted, rtl_pc, rtl_we, rtl_addr, rtl_wdata,
                             gate_halted, gate_pc, gate_we, gate_addr, gate_wdata);
            end
            if (rtl_we === 1'b1)
                rtl_writes = rtl_writes + 1;
            if (gate_we === 1'b1)
                gate_writes = gate_writes + 1;
        end
    endtask

    task check_bit;
        input            actual;
        input            expected;
        input [8*28-1:0] name;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : %b", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : %b (exp %b)", name, actual, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_gls.vcd");
        $dumpvars(1, tb_gls);   // top level only, the netlist is big

        $display("        program %0s", PROG);
        cycles      = 0;
        compared    = 0;
        mismatches  = 0;
        first_bad   = -1;
        rtl_writes  = 0;
        gate_writes = 0;

        rst = 1;
        @(negedge clk);
        @(negedge clk);
        compare;                 // cycle 0: end of reset
        rst = 0;

        while (!(rtl_halted === 1'b1 && gate_halted === 1'b1) && cycles < MAX_CYCLES) begin
            @(negedge clk);
            cycles = cycles + 1;
            compare;
        end

        // a few more cycles: both must stay halted and quiet
        repeat (3) begin
            @(negedge clk);
            compare;
        end

        check_bit(rtl_halted,  1'b1, "RTL reached HLT");
        check_bit(gate_halted, 1'b1, "gate reached HLT");

        if (mismatches == 0) begin
            pass_count = pass_count + 1;
            $display("PASS  lockstep compare : %0d cycles to HLT, %0d compared, 0 mismatches",
                     cycles, compared);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  lockstep compare : %0d of %0d cycles differ, first at cycle %0d (exp 0)",
                     mismatches, compared, first_bad);
        end

        if (rtl_writes == gate_writes) begin
            pass_count = pass_count + 1;
            $display("PASS  RAM write count : %0d on both", rtl_writes);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  RAM write count : gate %0d (exp %0d, RTL)", gate_writes, rtl_writes);
        end

        $display("------------------------------------------");
        $display("SUMMARY tb_gls: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
