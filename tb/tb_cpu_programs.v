`timescale 1ns/1ps

// Top-level program tests for NOVA-8 (step 8)
//
// Runs one CPU per test program, all at the same time, until every CPU
// reaches HLT. Then checks the final registers, RAM, flags, PC, the exact
// list of RAM writes and the number of clock cycles each program took.
//
// The last CPU runs countdown again but gets an extra reset in the middle
// of the program; it must still end exactly like the normal countdown,
// counted from that second reset.
//
// Cycles per instruction (from the FSM):
//   NOP 2, HLT 2, MOV/LDI/ALU 4, LD 4, ST 3, JMP 3, BR 3

module tb_cpu_programs;

    localparam NCPU = 8;
    localparam MAXW = 32;           // RAM writes logged per CPU
    localparam MID_RESET_AT = 61;   // countdown is in its 5th loop pass here

    reg clk = 0;
    reg rst;
    reg rst_mid = 0;                // extra reset, only for cpu_cd_reset

    // 0 smoke, 1 arith, 2 countdown, 3 memcopy, 4 fib, 5 branch, 6 misc,
    // 7 countdown with the mid-program reset
    wire [7:0]  halted;
    wire [7:0]  ram_we;
    wire [63:0] pc_bus, addr_bus, wdata_bus;   // 8 bits per CPU, CPU 0 in [7:0]
    wire        rst_cd = rst | rst_mid;

    integer pass_count = 0;
    integer fail_count = 0;
    integer cycles [0:NCPU-1];
    reg     [7:0] running;
    integer total, i, c;
    reg     mid_reset_done;
    reg     mid_was_running;

    reg [7:0] copy_data [0:7];

    // RAM writes as {addr, data}, MAXW entries per CPU
    reg [15:0] wlog [0:NCPU*MAXW-1];
    reg [15:0] wexp [0:NCPU*MAXW-1];
    integer    wcount [0:NCPU-1];
    integer    wexp_n [0:NCPU-1];

    nova8_top #(.PROG_FILE("programs/smoke.hex"))     cpu_smoke     (.clk(clk), .rst(rst), .halted(halted[0]),
        .pc_out(pc_bus[7:0]),   .ram_we(ram_we[0]), .ram_addr(addr_bus[7:0]),   .ram_wdata(wdata_bus[7:0]));
    nova8_top #(.PROG_FILE("programs/arith.hex"))     cpu_arith     (.clk(clk), .rst(rst), .halted(halted[1]),
        .pc_out(pc_bus[15:8]),  .ram_we(ram_we[1]), .ram_addr(addr_bus[15:8]),  .ram_wdata(wdata_bus[15:8]));
    nova8_top #(.PROG_FILE("programs/countdown.hex")) cpu_countdown (.clk(clk), .rst(rst), .halted(halted[2]),
        .pc_out(pc_bus[23:16]), .ram_we(ram_we[2]), .ram_addr(addr_bus[23:16]), .ram_wdata(wdata_bus[23:16]));
    nova8_top #(.PROG_FILE("programs/memcopy.hex"))   cpu_memcopy   (.clk(clk), .rst(rst), .halted(halted[3]),
        .pc_out(pc_bus[31:24]), .ram_we(ram_we[3]), .ram_addr(addr_bus[31:24]), .ram_wdata(wdata_bus[31:24]));
    nova8_top #(.PROG_FILE("programs/fib.hex"))       cpu_fib       (.clk(clk), .rst(rst), .halted(halted[4]),
        .pc_out(pc_bus[39:32]), .ram_we(ram_we[4]), .ram_addr(addr_bus[39:32]), .ram_wdata(wdata_bus[39:32]));
    nova8_top #(.PROG_FILE("programs/branch.hex"))    cpu_branch    (.clk(clk), .rst(rst), .halted(halted[5]),
        .pc_out(pc_bus[47:40]), .ram_we(ram_we[5]), .ram_addr(addr_bus[47:40]), .ram_wdata(wdata_bus[47:40]));
    nova8_top #(.PROG_FILE("programs/misc.hex"))      cpu_misc      (.clk(clk), .rst(rst), .halted(halted[6]),
        .pc_out(pc_bus[55:48]), .ram_we(ram_we[6]), .ram_addr(addr_bus[55:48]), .ram_wdata(wdata_bus[55:48]));
    nova8_top #(.PROG_FILE("programs/countdown.hex")) cpu_cd_reset  (.clk(clk), .rst(rst_cd), .halted(halted[7]),
        .pc_out(pc_bus[63:56]), .ram_we(ram_we[7]), .ram_addr(addr_bus[63:56]), .ram_wdata(wdata_bus[63:56]));

    always #5 clk = ~clk;

    // Log RAM writes on the falling edge, in the middle of the MEMORY cycle
    // of a ST (the write itself happens on the next rising edge).
    // An X on ram_we is logged too, so it shows up as a wrong write.
    always @(negedge clk) begin
        for (c = 0; c < NCPU; c = c + 1)
            if (ram_we[c] !== 1'b0) begin
                if (wcount[c] < MAXW)
                    wlog[c*MAXW + wcount[c]] = {addr_bus[8*c +: 8], wdata_bus[8*c +: 8]};
                wcount[c] = wcount[c] + 1;
            end
    end

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

    // same as check, but prints the RAM address
    task check_mem;
        input [7:0]      actual;
        input [7:0]      expected;
        input [8*16-1:0] prog;
        input [7:0]      addr;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s RAM[%h] : %h", prog, addr, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s RAM[%h] : %h (exp %h)", prog, addr, actual, expected);
            end
        end
    endtask

    task check_cycles;
        input integer    actual;
        input integer    expected;
        input [8*16-1:0] prog;
        begin
            if (actual == expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s cycles : %0d", prog, actual);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s cycles : %0d (exp %0d)", prog, actual, expected);
            end
        end
    endtask

    // add one write to the expected list of a CPU
    task exp_write;
        input integer t_cpu;
        input [7:0]   t_addr;
        input [7:0]   t_data;
        begin
            wexp[t_cpu*MAXW + wexp_n[t_cpu]] = {t_addr, t_data};
            wexp_n[t_cpu] = wexp_n[t_cpu] + 1;
        end
    endtask

    // compare the logged RAM writes with the expected list, in order;
    // on a mismatch print the first wrong write (xx = no such write)
    task check_writes;
        input integer    t_cpu;
        input [8*16-1:0] prog;
        integer          n, first;
        reg   [15:0]     act, expw;
        begin
            first = -1;
            for (n = 0; n < wexp_n[t_cpu]; n = n + 1)
                if (first < 0 && (n >= wcount[t_cpu] ||
                                  wlog[t_cpu*MAXW + n] !== wexp[t_cpu*MAXW + n]))
                    first = n;
            if (first < 0 && wcount[t_cpu] != wexp_n[t_cpu])
                first = wexp_n[t_cpu];   // more writes than expected
            if (first < 0) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s RAM writes : %0d, all in order", prog, wcount[t_cpu]);
            end else begin
                fail_count = fail_count + 1;
                act  = (first < wcount[t_cpu] && first < MAXW) ? wlog[t_cpu*MAXW + first] : 16'hxxxx;
                expw = (first < wexp_n[t_cpu]) ? wexp[t_cpu*MAXW + first] : 16'hxxxx;
                $display("FAIL  %0s RAM writes : %0d, #%0d RAM[%h] <= %h (exp %0d, #%0d RAM[%h] <= %h)",
                         prog, wcount[t_cpu], first, act[15:8], act[7:0],
                         wexp_n[t_cpu], first, expw[15:8], expw[7:0]);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_cpu_programs.vcd");
        $dumpvars(0, tb_cpu_programs);

        copy_data[0] = 8'hDE; copy_data[1] = 8'hAD;
        copy_data[2] = 8'hBE; copy_data[3] = 8'hEF;
        copy_data[4] = 8'h01; copy_data[5] = 8'h80;
        copy_data[6] = 8'h7F; copy_data[7] = 8'h00;

        for (i = 0; i < NCPU; i = i + 1) begin
            cycles[i] = 0;
            wcount[i] = 0;
            wexp_n[i] = 0;
        end

        // expected RAM writes, in program order
        exp_write(0, 8'h10, 8'h08);
        exp_write(1, 8'h20, 8'h4B); exp_write(1, 8'h21, 8'h2D); exp_write(1, 8'h22, 8'h0C);
        exp_write(1, 8'h23, 8'h3F); exp_write(1, 8'h24, 8'h33); exp_write(1, 8'h25, 8'hC3);
        exp_write(1, 8'h26, 8'h78); exp_write(1, 8'h27, 8'h1E); exp_write(1, 8'h28, 8'h78);
        exp_write(2, 8'h30, 8'h0A); exp_write(2, 8'h31, 8'h00);
        for (i = 0; i < 8; i = i + 1)
            exp_write(3, 8'h60 + i, copy_data[i]);
        for (i = 0; i < 8; i = i + 1)
            exp_write(3, 8'h70 + i, copy_data[i]);
        exp_write(4, 8'h40, 8'hE9); exp_write(4, 8'h41, 8'h90);
        for (i = 8'h50; i <= 8'h5A; i = i + 1)
            exp_write(5, i, 8'h01);
        for (i = 8'h80; i <= 8'h87; i = i + 1)
            exp_write(6, i, 8'h01);
        exp_write(6, 8'h90, 8'h5A); exp_write(6, 8'h91, 8'h5A);
        exp_write(6, 8'h88, 8'h01); exp_write(6, 8'h89, 8'h7F);
        exp_write(7, 8'h30, 8'h0A); exp_write(7, 8'h31, 8'h00);

        rst = 1;
        @(negedge clk);
        @(negedge clk);
        rst = 0;

        // run until every CPU has halted (or time out)
        total = 0;
        mid_reset_done  = 1'b0;
        mid_was_running = 1'b0;
        while (halted != 8'hFF && total < 5000) begin
            running = ~halted;
            if (!mid_reset_done)
                running[7] = 1'b0;   // cpu_cd_reset counts from its 2nd reset
            @(negedge clk);
            total = total + 1;
            for (i = 0; i < NCPU; i = i + 1)
                if (running[i])
                    cycles[i] = cycles[i] + 1;

            // two clocks of reset, released on a falling edge like rst
            if (total == MID_RESET_AT) begin
                mid_was_running = !halted[7] && cpu_cd_reset.u_rf.r2 != 8'h00;
                rst_mid = 1'b1;
            end
            if (total == MID_RESET_AT + 2) begin
                rst_mid = 1'b0;
                mid_reset_done = 1'b1;
                wcount[7] = 0;
            end
        end

        if (halted == 8'hFF) begin
            pass_count = pass_count + 1;
            $display("PASS  all 8 CPUs reached HLT");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  not halted after 5000 cycles, halted = %b (bit 0 = smoke)", halted);
        end

        // ---- smoke ----
        check(cpu_smoke.u_rf.r0,       8'h08, "smoke R0");
        check(cpu_smoke.u_rf.r1,       8'h01, "smoke R1");
        check(cpu_smoke.u_rf.r2,       8'h05, "smoke R2");
        check(cpu_smoke.u_rf.r3,       8'h00, "smoke R3");
        check_mem(cpu_smoke.u_ram.mem[8'h10], 8'h08, "smoke", 8'h10);
        check({4'h0, cpu_smoke.flags}, 8'h08, "smoke ZCNV=1000");
        check(pc_bus[7:0],             8'h0D, "smoke PC at HLT");
        check_writes(0, "smoke");
        check_cycles(cycles[0], 71, "smoke");

        // ---- arith ----
        check(cpu_arith.u_rf.r0,       8'h3C, "arith R0");
        check(cpu_arith.u_rf.r1,       8'h0F, "arith R1");
        check(cpu_arith.u_rf.r2,       8'h2D, "arith R2");
        check(cpu_arith.u_rf.r3,       8'h78, "arith R3");
        check_mem(cpu_arith.u_ram.mem[8'h20], 8'h4B, "arith ADD", 8'h20);
        check_mem(cpu_arith.u_ram.mem[8'h21], 8'h2D, "arith SUB", 8'h21);
        check_mem(cpu_arith.u_ram.mem[8'h22], 8'h0C, "arith AND", 8'h22);
        check_mem(cpu_arith.u_ram.mem[8'h23], 8'h3F, "arith OR",  8'h23);
        check_mem(cpu_arith.u_ram.mem[8'h24], 8'h33, "arith XOR", 8'h24);
        check_mem(cpu_arith.u_ram.mem[8'h25], 8'hC3, "arith NOT", 8'h25);
        check_mem(cpu_arith.u_ram.mem[8'h26], 8'h78, "arith SHL", 8'h26);
        check_mem(cpu_arith.u_ram.mem[8'h27], 8'h1E, "arith SHR", 8'h27);
        check_mem(cpu_arith.u_ram.mem[8'h28], 8'h78, "arith LD+ADD", 8'h28);
        check({4'h0, cpu_arith.flags}, 8'h00, "arith ZCNV=0000");
        check(pc_bus[15:8],            8'h1F, "arith PC at HLT");
        check_writes(1, "arith");
        check_cycles(cycles[1], 113, "arith");

        // ---- countdown ----
        check(cpu_countdown.u_rf.r0,   8'h00, "countdown R0");
        check(cpu_countdown.u_rf.r1,   8'h01, "countdown R1");
        check(cpu_countdown.u_rf.r2,   8'h0A, "countdown R2 (passes)");
        check(cpu_countdown.u_rf.r3,   8'h00, "countdown R3");
        check_mem(cpu_countdown.u_ram.mem[8'h30], 8'h0A, "countdown", 8'h30);
        check_mem(cpu_countdown.u_ram.mem[8'h31], 8'h00, "countdown", 8'h31);
        check({4'h0, cpu_countdown.flags}, 8'h08, "countdown ZCNV=1000");
        check(pc_bus[23:16],           8'h09, "countdown PC at HLT");
        check_writes(2, "countdown");
        check_cycles(cycles[2], 130, "countdown");

        // ---- memcopy ----
        for (i = 0; i < 8; i = i + 1) begin
            check_mem(cpu_memcopy.u_ram.mem[8'h60 + i], copy_data[i], "memcopy src", 8'h60 + i);
            check_mem(cpu_memcopy.u_ram.mem[8'h70 + i], copy_data[i], "memcopy dst", 8'h70 + i);
        end
        check(cpu_memcopy.u_rf.r0,     8'h00, "memcopy R0");
        check(cpu_memcopy.u_rf.r1,     8'h00, "memcopy R1");
        check({4'h0, cpu_memcopy.flags}, 8'h00, "memcopy ZCNV=0000");
        check(pc_bus[31:24],           8'h21, "memcopy PC at HLT");
        check_writes(3, "memcopy");
        check_cycles(cycles[3], 114, "memcopy");

        // ---- fib ----
        check(cpu_fib.u_rf.r0,         8'h90, "fib R0 = F12 = 144");
        check(cpu_fib.u_rf.r1,         8'hE9, "fib R1 = F13 = 233");
        check(cpu_fib.u_rf.r2,         8'h00, "fib R2");
        check(cpu_fib.u_rf.r3,         8'h01, "fib R3");
        check_mem(cpu_fib.u_ram.mem[8'h40], 8'hE9, "fib F13", 8'h40);
        check_mem(cpu_fib.u_ram.mem[8'h41], 8'h90, "fib F12", 8'h41);
        check({4'h0, cpu_fib.flags}, 8'h08, "fib ZCNV=1000");
        check(pc_bus[39:32],           8'h0D, "fib PC at HLT");
        check_writes(4, "fib");
        check_cycles(cycles[4], 344, "fib");

        // ---- branch ----
        for (i = 8'h50; i <= 8'h5A; i = i + 1)
            check_mem(cpu_branch.u_ram.mem[i], 8'h01, "branch test", i);
        check(cpu_branch.u_rf.r0,      8'h7F, "branch R0");
        check(cpu_branch.u_rf.r1,      8'h01, "branch R1");
        check(cpu_branch.u_rf.r2,      8'h01, "branch R2");
        check(cpu_branch.u_rf.r3,      8'hEE, "branch R3");
        check({4'h0, cpu_branch.flags}, 8'h01, "branch ZCNV=0001 (V)");
        check(pc_bus[47:40],           8'h3C, "branch PC at HLT");
        check_writes(5, "branch");
        check_cycles(cycles[5], 140, "branch");

        // ---- misc ----
        for (i = 8'h80; i <= 8'h88; i = i + 1)
            check_mem(cpu_misc.u_ram.mem[i], 8'h01, "misc test", i);
        check_mem(cpu_misc.u_ram.mem[8'h89], 8'h7F, "misc V chain", 8'h89);
        check_mem(cpu_misc.u_ram.mem[8'h90], 8'h5A, "misc ST", 8'h90);
        check_mem(cpu_misc.u_ram.mem[8'h91], 8'h5A, "misc LD+ST", 8'h91);
        check(cpu_misc.u_rf.r0,        8'h7F, "misc R0");
        check(cpu_misc.u_rf.r1,        8'h01, "misc R1");
        check(cpu_misc.u_rf.r2,        8'h01, "misc R2");
        check(cpu_misc.u_rf.r3,        8'hEE, "misc R3");
        check({4'h0, cpu_misc.flags},  8'h01, "misc ZCNV=0001 (V kept)");
        check(pc_bus[55:48],           8'h40, "misc PC at HLT");
        check_writes(6, "misc");
        check_cycles(cycles[6], 168, "misc");

        // ---- countdown, reset in the middle ----
        check({7'd0, mid_was_running}, 8'h01, "cd_reset running at reset");
        check(cpu_cd_reset.u_rf.r0,    8'h00, "cd_reset R0");
        check(cpu_cd_reset.u_rf.r1,    8'h01, "cd_reset R1");
        check(cpu_cd_reset.u_rf.r2,    8'h0A, "cd_reset R2 (passes)");
        check(cpu_cd_reset.u_rf.r3,    8'h00, "cd_reset R3");
        check_mem(cpu_cd_reset.u_ram.mem[8'h30], 8'h0A, "cd_reset", 8'h30);
        check_mem(cpu_cd_reset.u_ram.mem[8'h31], 8'h00, "cd_reset", 8'h31);
        check({4'h0, cpu_cd_reset.flags}, 8'h08, "cd_reset ZCNV=1000");
        check(pc_bus[63:56],           8'h09, "cd_reset PC at HLT");
        check_writes(7, "cd_reset");
        check_cycles(cycles[7], 130, "cd_reset");

        $display("------------------------------------------");
        $display("SUMMARY tb_cpu_programs: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
