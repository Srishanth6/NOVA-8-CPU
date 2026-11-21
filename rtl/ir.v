`timescale 1ns/1ps

// NOVA-8 instruction register (16 bits)
// Also splits the instruction into its fields:
//   [15:12] opcode | [11:10] rd | [9:8] rs | [7:0] imm8 / address

module ir (
    input  wire        clk,
    input  wire        rst,
    input  wire        ir_load,
    input  wire [15:0] ir_in,
    output reg  [15:0] ir_out,
    output wire [3:0]  opcode,
    output wire [1:0]  rd,
    output wire [1:0]  rs,
    output wire [7:0]  imm8
);

    always @(posedge clk) begin
        if (rst)
            ir_out <= 16'h0000;  // 0x0000 = NOP
        else if (ir_load)
            ir_out <= ir_in;
    end

    assign opcode = ir_out[15:12];
    assign rd     = ir_out[11:10];
    assign rs     = ir_out[9:8];
    assign imm8   = ir_out[7:0];

endmodule
