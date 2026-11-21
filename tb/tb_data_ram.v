`timescale 1ns/1ps

// Self-checking testbench for data_ram.v

module tb_data_ram;

    reg        clk = 0;
    reg        w_en;
    reg  [7:0] addr;
    reg  [7:0] w_data;
    wire [7:0] r_data;

    integer pass_count = 0;
    integer fail_count = 0;
    integer i, bad;

    data_ram dut (
        .clk    (clk),
        .w_en   (w_en),
        .addr   (addr),
        .w_data (w_data),
        .r_data (r_data)
    );

    always #5 clk = ~clk;

    task write_mem;
        input [7:0] t_addr;
        input [7:0] t_data;
        begin
            @(negedge clk);
            w_en   = 1'b1;
            addr   = t_addr;
            w_data = t_data;
            @(negedge clk);
            w_en   = 1'b0;
        end
    endtask

    // combinational read: no clock needed
    task check_read;
        input [7:0]      t_addr;
        input [7:0]      expected;
        input [8*28-1:0] name;
        begin
            addr = t_addr;
            #1;
            if (r_data === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : ram[%h]=%h", name, t_addr, r_data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : ram[%h]=%h (exp %h)", name, t_addr, r_data, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_data_ram.vcd");
        $dumpvars(0, tb_data_ram);

        w_en = 0; addr = 0; w_data = 0;

        // 1. write a few addresses, including both ends
        write_mem(8'h00, 8'h11);
        write_mem(8'h01, 8'h22);
        write_mem(8'h7F, 8'h80);
        write_mem(8'h80, 8'h5A);
        write_mem(8'hFF, 8'hFF);

        check_read(8'h00, 8'h11, "read 00");
        check_read(8'h01, 8'h22, "read 01");
        check_read(8'h7F, 8'h80, "read 7F");
        check_read(8'h80, 8'h5A, "read 80");
        check_read(8'hFF, 8'hFF, "read FF");

        // 2. w_en = 0 must not write
        @(negedge clk);
        w_en = 1'b0; addr = 8'h01; w_data = 8'h99;
        @(negedge clk);
        check_read(8'h01, 8'h22, "w_en=0 does not write");

        // 3. overwrite one address, neighbours unchanged
        write_mem(8'h7F, 8'h00);
        check_read(8'h7F, 8'h00, "overwrite 7F");
        check_read(8'h80, 8'h5A, "80 unchanged");
        check_read(8'h00, 8'h11, "00 unchanged");

        // 4. write is synchronous: old value until the clock edge
        @(negedge clk);
        w_en = 1'b1; addr = 8'h01; w_data = 8'hC3;
        #1;
        if (r_data === 8'h22) begin
            pass_count = pass_count + 1;
            $display("PASS  before edge still old : ram[01]=%h", r_data);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  before edge still old : ram[01]=%h (exp 22)", r_data);
        end
        @(negedge clk);
        w_en = 1'b0;
        check_read(8'h01, 8'hC3, "after edge updated");

        // 5. fill every address with a pattern, then read all back
        for (i = 0; i < 256; i = i + 1)
            write_mem(i, i ^ 8'hA5);
        bad = 0;
        for (i = 0; i < 256; i = i + 1) begin
            addr = i;
            #1;
            if (r_data !== (i ^ 8'hA5))
                bad = bad + 1;
        end
        if (bad == 0) begin
            pass_count = pass_count + 1;
            $display("PASS  all 256 addresses (addr ^ A5)");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL  all 256 addresses : %0d bad", bad);
        end

        $display("------------------------------------------");
        $display("SUMMARY tb_data_ram: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
