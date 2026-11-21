`timescale 1ns/1ps

// NOVA-8 instruction ROM: 256 x 16, combinational read
// The hex file must have all 256 words (assembler.py pads with 0000 = NOP).
// Don't add a zero-fill loop before $readmemh: Yosys applies the loop
// after the file and the ROM would synthesize as all zeros.

module instr_rom #(
    parameter INIT_FILE = "programs/program.hex"
) (
    input  wire [7:0]  addr,
    output wire [15:0] data
);

    reg [15:0] mem [0:255];

    initial $readmemh(INIT_FILE, mem);

    assign data = mem[addr];

endmodule
