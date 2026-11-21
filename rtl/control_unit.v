`timescale 1ns/1ps

// NOVA-8 control unit (multi-cycle FSM)
//
// State sequence per instruction type:
//   NOP              FETCH -> DECODE -> FETCH
//   MOV, LDI, ALU    FETCH -> DECODE -> EXECUTE -> WRITEBACK -> FETCH
//   LD               FETCH -> DECODE -> MEMORY  -> WRITEBACK -> FETCH
//   ST               FETCH -> DECODE -> MEMORY  -> FETCH
//   JMP, BR          FETCH -> DECODE -> EXECUTE -> FETCH
//   HLT              FETCH -> DECODE -> HALT (stays until reset)
//
// What each state does:
//   FETCH      IR <= ROM[PC], PC <= PC + 1
//   DECODE     IR fields settle, next state is picked from the opcode
//              (register reads are combinational, used in EXECUTE / MEMORY)
//   EXECUTE    ALU result -> alu_out (and flags for ALU ops), or PC <= target
//   MEMORY     LD: mdr <= RAM[addr]   ST: RAM[addr] <= rd
//   WRITEBACK  rd <= alu_out or mdr
//
// The opcode comes from the IR, so it is only valid from DECODE onwards.
// FETCH never looks at it.

module control_unit (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] opcode,
    input  wire [1:0] cond,      // rs field, used as branch condition
    input  wire [3:0] flags,     // {Z, C, N, V}

    output reg  [2:0] state,

    output reg        ir_load,
    output reg        pc_inc,
    output reg        pc_load,
    output reg        reg_we,
    output reg        flags_we,
    output reg        alu_load,
    output reg        mem_we,
    output reg        mdr_load,

    output wire       alu_b_sel, // 0 = rs, 1 = imm8
    output wire       wb_sel,    // 0 = alu_out, 1 = mdr
    output wire       halted
);

    localparam S_FETCH     = 3'd0;
    localparam S_DECODE    = 3'd1;
    localparam S_EXECUTE   = 3'd2;
    localparam S_MEMORY    = 3'd3;
    localparam S_WRITEBACK = 3'd4;
    localparam S_HALT      = 3'd5;

    localparam OP_NOP = 4'h0;
    localparam OP_MOV = 4'h1;
    localparam OP_LDI = 4'h2;
    localparam OP_ADD = 4'h3;
    localparam OP_SHR = 4'hA;
    localparam OP_LD  = 4'hB;
    localparam OP_ST  = 4'hC;
    localparam OP_JMP = 4'hD;
    localparam OP_BR  = 4'hE;
    localparam OP_HLT = 4'hF;

    // ALU ops (ADD..SHR) update the flags
    wire is_alu    = (opcode >= OP_ADD) && (opcode <= OP_SHR);
    // anything that writes rd through the ALU path
    wire is_reg_op = is_alu || (opcode == OP_MOV) || (opcode == OP_LDI);

    // branch condition: 00 = Z, 01 = C, 10 = N, 11 = not Z
    reg branch_taken;
    always @(*) begin
        case (cond)
            2'b00:   branch_taken = flags[3];
            2'b01:   branch_taken = flags[2];
            2'b10:   branch_taken = flags[1];
            default: branch_taken = ~flags[3];
        endcase
    end

    // state register
    reg [2:0] next_state;
    always @(posedge clk) begin
        if (rst)
            state <= S_FETCH;
        else
            state <= next_state;
    end

    // next state logic
    always @(*) begin
        case (state)
            S_FETCH:  next_state = S_DECODE;
            S_DECODE: begin
                case (opcode)
                    OP_NOP:       next_state = S_FETCH;
                    OP_HLT:       next_state = S_HALT;
                    OP_LD, OP_ST: next_state = S_MEMORY;
                    default:      next_state = S_EXECUTE;  // ALU, MOV, LDI, JMP, BR
                endcase
            end
            S_EXECUTE:   next_state = is_reg_op ? S_WRITEBACK : S_FETCH;
            S_MEMORY:    next_state = (opcode == OP_LD) ? S_WRITEBACK : S_FETCH;
            S_WRITEBACK: next_state = S_FETCH;
            S_HALT:      next_state = S_HALT;
            default:     next_state = S_FETCH;
        endcase
    end

    // control outputs
    always @(*) begin
        ir_load  = 1'b0;
        pc_inc   = 1'b0;
        pc_load  = 1'b0;
        reg_we   = 1'b0;
        flags_we = 1'b0;
        alu_load = 1'b0;
        mem_we   = 1'b0;
        mdr_load = 1'b0;

        case (state)
            S_FETCH: begin
                ir_load = 1'b1;
                pc_inc  = 1'b1;
            end
            S_EXECUTE: begin
                alu_load = is_reg_op;
                flags_we = is_alu;
                pc_load  = (opcode == OP_JMP) || ((opcode == OP_BR) && branch_taken);
            end
            S_MEMORY: begin
                mdr_load = (opcode == OP_LD);
                mem_we   = (opcode == OP_ST);
            end
            S_WRITEBACK: reg_we = 1'b1;
            default: ;
        endcase
    end

    assign alu_b_sel = (opcode == OP_LDI);
    assign wb_sel    = (opcode == OP_LD);
    assign halted    = (state == S_HALT);

endmodule
