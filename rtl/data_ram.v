`timescale 1ns/1ps

// NOVA-8 data RAM: 256 x 8
// Synchronous write, combinational read, one shared address.
// No reset (like a real SRAM), so contents are X until written.

module data_ram (
    input  wire       clk,
    input  wire       w_en,
    input  wire [7:0] addr,
    input  wire [7:0] w_data,
    output wire [7:0] r_data
);

    reg [7:0] mem [0:255];

    always @(posedge clk) begin
        if (w_en)
            mem[addr] <= w_data;
    end

    assign r_data = mem[addr];

endmodule
