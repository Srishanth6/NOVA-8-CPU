`timescale 1ns/1ps

// Smoke test for nova8_top.v
// Runs programs/smoke.hex until HLT and checks registers, RAM, flags and PC.
// Step 8 adds the full set of test programs.

module tb_nova8_top;

    reg        clk = 0;
    reg        rst;
    wire       halted;
    wire [7:0] pc_out;
    wire       ram_we;
    wire [7:0] ram_addr, ram_wdata;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycles;

    nova8_top #(.PROG_FILE("programs/smoke.hex")) dut (
        .clk       (clk),
        .rst       (rst),
        .halted    (halted),
        .pc_out    (pc_out),
        .ram_we    (ram_we),
        .ram_addr  (ram_addr),
        .ram_wdata (ram_wdata)
    );

    always #5 clk = ~clk;

    task check;
        input [7:0]      actual;
        input [7:0]      expected;
        input [8*28-1:0] name;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : %h", name, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : %h (exp %h)", name, actual, expected);
            end
        end
    endtask

    // print every register write and RAM write while the program runs
    always @(posedge clk) begin
        if (!rst && dut.reg_we)
            $display("        pc=%h  R%0d <= %h", pc_out, dut.rd, dut.wb_data);
        if (!rst && ram_we)
            $display("        pc=%h  RAM[%h] <= %h", pc_out, ram_addr, ram_wdata);
    end

    initial begin
        $dumpfile("sim/tb_nova8_top.vcd");
        $dumpvars(0, tb_nova8_top);

        rst = 1;
        @(negedge clk);
        @(negedge clk);
        rst = 0;

        // run until HLT, with a timeout in case it never halts
        cycles = 0;
        while (!halted && cycles < 2000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end

        if (halted) begin
            pass_count = pass_count + 1;
            $display("PASS  reached HLT after %0d cycles", cycles);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  did not reach HLT within 2000 cycles");
        end

        check(dut.u_rf.r0,       8'h08, "R0");
        check(dut.u_rf.r1,       8'h01, "R1");
        check(dut.u_rf.r2,       8'h05, "R2");
        check(dut.u_rf.r3,       8'h00, "R3 (loop counted to 0)");
        check(dut.u_ram.mem[16], 8'h08, "RAM[10]");
        check({4'h0, dut.flags}, 8'h08, "flags ZCNV = 1000");
        check(pc_out,            8'h0D, "PC after HLT");

        $display("------------------------------------------");
        $display("SUMMARY tb_nova8_top: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
