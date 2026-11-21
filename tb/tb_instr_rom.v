`timescale 1ns/1ps

// Self-checking testbench for instr_rom.v
// Loads tb/rom_test.hex (all 256 words listed, like assembler.py output)
// and checks the few non-zero words, plus that every other word is 0000.

module tb_instr_rom;

    reg  [7:0]  addr;
    wire [15:0] data;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i, bad;

    instr_rom #(.INIT_FILE("tb/rom_test.hex")) dut (
        .addr (addr),
        .data (data)
    );

    task check;
        input [7:0]      t_addr;
        input [15:0]     expected;
        input [8*28-1:0] name;
        begin
            addr = t_addr;
            #10;
            if (data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : rom[%h]=%h", name, t_addr, data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : rom[%h]=%h (exp %h)", name, t_addr, data, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_instr_rom.vcd");
        $dumpvars(0, tb_instr_rom);

        check(8'h00, 16'h1234, "first word");
        check(8'h01, 16'hABCD, "second word");
        check(8'h02, 16'h0000, "zero word in file");
        check(8'h03, 16'hFFFF, "all ones word");
        check(8'h80, 16'h5A5A, "middle word 80");
        check(8'hFF, 16'hF000, "last address FF");
        check(8'h00, 16'h1234, "re-read address 00");

        // every other word in the file is 0000 (NOP)
        bad = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (i > 3 && i != 8'h80 && i != 8'hFF) begin
                addr = i;
                #1;
                if (data !== 16'h0000)
                    bad = bad + 1;
            end
        end
        if (bad == 0) begin
            pass_count = pass_count + 1;
            $display("PASS  other 250 words are 0000");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  other 250 words are 0000 : %0d bad words (exp 0)", bad);
        end

        $display("------------------------------------------");
        $display("SUMMARY tb_instr_rom: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
