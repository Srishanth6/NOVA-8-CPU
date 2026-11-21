`timescale 1ns/1ps

// NOVA-8 ALU (purely combinational)
//
// alu_op is the instruction opcode itself, so IR[15:12] can drive it directly.
// Flags are packed as {Z, C, N, V}. A flag that an op doesn't touch is passed
// through unchanged from flags_in, so the flags register can simply load
// flags_out after any instruction.
//
// For non-ALU opcodes (NOP, MOV, LDI, ...) result = b and flags are untouched.
// The datapath uses this pass-through for MOV (b = rs) and LDI (b = imm8).

module alu (
    input  wire [3:0] alu_op,
    input  wire [7:0] a,         // rd value
    input  wire [7:0] b,         // rs value or imm8
    input  wire [3:0] flags_in,  // current {Z, C, N, V}
    output reg  [7:0] result,
    output wire [3:0] flags_out  // new {Z, C, N, V}
);

    localparam OP_ADD = 4'h3;
    localparam OP_SUB = 4'h4;
    localparam OP_AND = 4'h5;
    localparam OP_OR  = 4'h6;
    localparam OP_XOR = 4'h7;
    localparam OP_NOT = 4'h8;
    localparam OP_SHL = 4'h9;
    localparam OP_SHR = 4'hA;

    reg [8:0] sum9;  // one extra bit to catch carry / borrow
    reg       c, v;

    // Z and N are only updated by ALU ops (0x3 to 0xA)
    wire is_alu_op = (alu_op >= OP_ADD) && (alu_op <= OP_SHR);

    always @(*) begin
        // defaults: pass b through, keep old C and V
        result = b;
        sum9   = 9'd0;
        c      = flags_in[2];
        v      = flags_in[0];

        case (alu_op)
            OP_ADD: begin
                sum9   = {1'b0, a} + {1'b0, b};
                result = sum9[7:0];
                c      = sum9[8];
                // overflow: both inputs same sign, result sign differs
                v      = (a[7] == b[7]) && (result[7] != a[7]);
            end
            OP_SUB: begin
                sum9   = {1'b0, a} - {1'b0, b};
                result = sum9[7:0];
                c      = sum9[8];  // 1 = borrow (a < b unsigned)
                // overflow: inputs have different signs, result sign differs from a
                v      = (a[7] != b[7]) && (result[7] != a[7]);
            end
            OP_AND: result = a & b;
            OP_OR:  result = a | b;
            OP_XOR: result = a ^ b;
            OP_NOT: result = ~a;
            OP_SHL: begin
                result = {a[6:0], 1'b0};
                c      = a[7];  // bit shifted out
            end
            OP_SHR: begin
                result = {1'b0, a[7:1]};  // logical shift
                c      = a[0];
            end
            default: ;  // keep defaults
        endcase
    end

    assign flags_out = is_alu_op ? {(result == 8'h00), c, result[7], v} : flags_in;

endmodule
