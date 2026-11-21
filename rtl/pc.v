`timescale 1ns/1ps

// NOVA-8 program counter (8 bits, 256 instruction words)
// pc_load has priority over pc_inc. Incrementing past 0xFF wraps to 0x00.

module pc (
    input  wire       clk,
    input  wire       rst,
    input  wire       pc_load,  // jump / taken branch
    input  wire       pc_inc,   // next instruction
    input  wire [7:0] pc_in,    // jump target
    output reg  [7:0] pc_out
);

    always @(posedge clk) begin
        if (rst)
            pc_out <= 8'h00;
        else if (pc_load)
            pc_out <= pc_in;
        else if (pc_inc)
            pc_out <= pc_out + 8'd1;
    end

endmodule
