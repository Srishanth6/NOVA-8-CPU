`timescale 1ns/1ps

// Self-checking testbench for control_unit.v
//
// For each instruction the testbench walks the FSM one clock at a time and
// checks the state AND the control strobes in every state, so a strobe in
// the wrong state (or for two cycles) is caught.
//
// IR timing is copied from the real CPU: during FETCH the opcode input
// still holds an older instruction ("stale" column), and the real opcode
// only appears just after the rising edge that leaves FETCH. So anything
// in FETCH that looks at the opcode shows up as a failure.
//
// State sequences are printed in octal, one digit per state:
//   0 = FETCH  1 = DECODE  2 = EXECUTE  3 = MEMORY  4 = WRITEBACK  5 = HALT
// Strobes are printed as one hex byte per state, bits
//   {ir_load, pc_inc, pc_load, reg_we, flags_we, alu_load, mem_we, mdr_load}

module tb_control_unit;

    reg        clk = 0;
    reg        rst;
    reg  [3:0] opcode;
    reg  [1:0] cond;
    reg  [3:0] flags;

    wire [2:0] state;
    wire       ir_load, pc_inc, pc_load, reg_we, flags_we, alu_load, mem_we, mdr_load;
    wire       alu_b_sel, wb_sel, halted;

    localparam [2:0] F = 3'd0, D = 3'd1, E = 3'd2, M = 3'd3, W = 3'd4, H = 3'd5;

    // expected strobes in one state
    localparam [7:0] SB_FETCH = 8'b1100_0000;  // ir_load, pc_inc
    localparam [7:0] SB_NONE  = 8'b0000_0000;
    localparam [7:0] SB_MOV   = 8'b0000_0100;  // alu_load (MOV, LDI)
    localparam [7:0] SB_ALU   = 8'b0000_1100;  // flags_we, alu_load
    localparam [7:0] SB_JUMP  = 8'b0010_0000;  // pc_load
    localparam [7:0] SB_LD    = 8'b0000_0001;  // mdr_load
    localparam [7:0] SB_ST    = 8'b0000_0010;  // mem_we
    localparam [7:0] SB_WB    = 8'b0001_0000;  // reg_we

    wire [7:0] strobes = {ir_load, pc_inc, pc_load, reg_we,
                          flags_we, alu_load, mem_we, mdr_load};

    integer pass_count = 0;
    integer fail_count = 0;

    control_unit dut (
        .clk       (clk),
        .rst       (rst),
        .opcode    (opcode),
        .cond      (cond),
        .flags     (flags),
        .state     (state),
        .ir_load   (ir_load),
        .pc_inc    (pc_inc),
        .pc_load   (pc_load),
        .reg_we    (reg_we),
        .flags_we  (flags_we),
        .alu_load  (alu_load),
        .mem_we    (mem_we),
        .mdr_load  (mdr_load),
        .alu_b_sel (alu_b_sel),
        .wb_sel    (wb_sel),
        .halted    (halted)
    );

    always #5 clk = ~clk;

    // Run one instruction, called in FETCH just after a falling edge.
    // exp_seq holds up to 5 states and exp_str the strobes for each of
    // them, first state in the top bits. The last state listed is where the
    // FSM should end up: only its state is checked, its strobes belong to
    // the next instruction (put SB_NONE there).
    task check_seq;
        input [3:0]      t_stale;  // opcode left in the IR during FETCH
        input [3:0]      t_op;
        input [1:0]      t_cond;
        input [3:0]      t_flags;
        input [14:0]     exp_seq;
        input [39:0]     exp_str;
        input [2:0]      len;
        input [8*28-1:0] name;
        reg   [14:0]     act_seq;
        reg   [39:0]     act_str;
        reg   [39:0]     mask;
        integer          k;
        begin
            opcode  = t_stale;
            cond    = ~t_cond;
            flags   = t_flags;
            act_seq = 15'd0;
            act_str = 40'd0;
            mask    = 40'd0;
            for (k = 0; k < len; k = k + 1) begin
                #1;
                act_seq[14 - 3*k -: 3] = state;
                if (k < len - 1) begin
                    act_str[39 - 8*k -: 8] = strobes;
                    mask[39 - 8*k -: 8]    = 8'hFF;
                    if (k == 0) begin
                        // the IR loads on this edge
                        @(posedge clk);
                        #1;
                        opcode = t_op;
                        cond   = t_cond;
                    end
                    @(negedge clk);
                end
            end
            if (act_seq === exp_seq && act_str === (exp_str & mask)) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : states=%o strobes=%h", name, act_seq, act_str);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : states=%o (exp %o) strobes=%h (exp %h)",
                         name, act_seq, exp_seq, act_str, exp_str & mask);
            end
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

    task check_state;
        input [2:0]      expected;
        input [8*28-1:0] name;
        begin
            #1;
            if (state === expected) begin
                pass_count = pass_count + 1;
                $display("PASS  %0s : state=%0d", name, state);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL  %0s : state=%0d (exp %0d)", name, state, expected);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_control_unit.vcd");
        $dumpvars(0, tb_control_unit);

        rst = 1; opcode = 4'h0; cond = 2'b00; flags = 4'b0000;
        @(negedge clk);
        @(negedge clk);
        check_state(F, "reset -> FETCH");

        // datapath mux selects are pure decode of the opcode,
        // checked while the FSM is held in reset
        @(negedge clk);
        opcode = 4'h2; #1; check_bit(alu_b_sel, 1'b1, "LDI alu_b_sel = imm");
        opcode = 4'h1; #1; check_bit(alu_b_sel, 1'b0, "MOV alu_b_sel = rs");
        opcode = 4'hB; #1; check_bit(wb_sel,    1'b1, "LD  wb_sel = mdr");
        opcode = 4'h3; #1; check_bit(wb_sel,    1'b0, "ADD wb_sel = alu_out");
        @(negedge clk);
        rst = 0;

        //       stale  op    cond   flags    states
        //       strobes per state                                       len
        check_seq(4'hF, 4'h0, 2'b00, 4'b0000, {F,D,F,3'd0,3'd0},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        3, "NOP");
        check_seq(4'h0, 4'h1, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_MOV,  SB_WB,   SB_NONE},        5, "MOV (no flags)");
        check_seq(4'h1, 4'h2, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_MOV,  SB_WB,   SB_NONE},        5, "LDI (no flags)");
        check_seq(4'h2, 4'h3, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "ADD");
        check_seq(4'h3, 4'h4, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "SUB");
        check_seq(4'h4, 4'h5, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "AND");
        check_seq(4'h5, 4'h6, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "OR");
        check_seq(4'h6, 4'h7, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "XOR");
        check_seq(4'h7, 4'h8, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "NOT");
        check_seq(4'h8, 4'h9, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "SHL");
        check_seq(4'h9, 4'hA, 2'b00, 4'b0000, {F,D,E,W,F},
                  {SB_FETCH, SB_NONE, SB_ALU,  SB_WB,   SB_NONE},        5, "SHR");
        check_seq(4'hA, 4'hB, 2'b00, 4'b0000, {F,D,M,W,F},
                  {SB_FETCH, SB_NONE, SB_LD,   SB_WB,   SB_NONE},        5, "LD");
        check_seq(4'hB, 4'hC, 2'b00, 4'b0000, {F,D,M,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_ST,   SB_NONE, SB_NONE},        4, "ST");
        check_seq(4'hC, 4'hD, 2'b00, 4'b0000, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_JUMP, SB_NONE, SB_NONE},        4, "JMP");

        // branches: flags are {Z, C, N, V}; the stale opcode is HLT or LD,
        // which would send a FETCH that looks at the opcode somewhere else
        check_seq(4'hD, 4'hE, 2'b00, 4'b1000, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_JUMP, SB_NONE, SB_NONE},        4, "BRZ  Z=1 taken");
        check_seq(4'hF, 4'hE, 2'b00, 4'b0111, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        4, "BRZ  Z=0 not taken");
        check_seq(4'hB, 4'hE, 2'b01, 4'b0100, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_JUMP, SB_NONE, SB_NONE},        4, "BRC  C=1 taken");
        check_seq(4'hF, 4'hE, 2'b01, 4'b1011, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        4, "BRC  C=0 not taken");
        check_seq(4'hB, 4'hE, 2'b10, 4'b0010, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_JUMP, SB_NONE, SB_NONE},        4, "BRN  N=1 taken");
        check_seq(4'hF, 4'hE, 2'b10, 4'b1101, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        4, "BRN  N=0 not taken");
        check_seq(4'hB, 4'hE, 2'b11, 4'b0000, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_JUMP, SB_NONE, SB_NONE},        4, "BRNZ Z=0 taken");
        check_seq(4'hF, 4'hE, 2'b11, 4'b1000, {F,D,E,F,3'd0},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        4, "BRNZ Z=1 not taken");

        // reset in the middle of an instruction goes back to FETCH
        opcode = 4'h3;
        @(negedge clk);                        // now in DECODE
        @(negedge clk);                        // now in EXECUTE
        check_state(E, "ADD reached EXECUTE");
        rst = 1;
        @(negedge clk);
        rst = 0;
        check_state(F, "reset mid-instr -> FETCH");

        // HLT stays in HALT, with no strobes
        check_seq(4'h3, 4'hF, 2'b00, 4'b0000, {F,D,H,H,H},
                  {SB_FETCH, SB_NONE, SB_NONE, SB_NONE, SB_NONE},        5, "HLT");
        check_bit(halted, 1'b1, "halted = 1");
        opcode = 4'h0;                         // opcode changes must not matter
        repeat (5) @(negedge clk);
        check_state(H, "still HALT after 5 clocks");
        check_bit(ir_load | pc_inc, 1'b0, "no fetch while halted");
        check_bit(|strobes, 1'b0, "no strobes while halted");

        rst = 1;
        @(negedge clk);
        rst = 0;
        check_state(F, "reset leaves HALT");
        check_bit(halted, 1'b0, "halted = 0 after reset");

        $display("------------------------------------------");
        $display("SUMMARY tb_control_unit: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("RESULT: ALL TESTS PASSED");
        else
            $display("RESULT: SOME TESTS FAILED");
        $finish;
    end

endmodule
