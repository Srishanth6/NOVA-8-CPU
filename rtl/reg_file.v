`timescale 1ns/1ps

// NOVA-8 register file: R0-R3, 8 bits each
// Two combinational read ports, one synchronous write port.
// Reset clears all registers. A write shows up on the read ports
// after the clock edge (no write-through bypass).

module reg_file (
    input  wire       clk,
    input  wire       rst,

    input  wire       w_en,
    input  wire [1:0] w_addr,
    input  wire [7:0] w_data,

    input  wire [1:0] addr_a,
    output reg  [7:0] data_a,

    input  wire [1:0] addr_b,
    output reg  [7:0] data_b
);

    reg [7:0] r0, r1, r2, r3;

    // write port
    always @(posedge clk) begin
        if (rst) begin
            r0 <= 8'h00;
            r1 <= 8'h00;
            r2 <= 8'h00;
            r3 <= 8'h00;
        end else if (w_en) begin
            case (w_addr)
                2'd0: r0 <= w_data;
                2'd1: r1 <= w_data;
                2'd2: r2 <= w_data;
                2'd3: r3 <= w_data;
            endcase
        end
    end

    // read port A
    always @(*) begin
        case (addr_a)
            2'd0:    data_a = r0;
            2'd1:    data_a = r1;
            2'd2:    data_a = r2;
            default: data_a = r3;
        endcase
    end

    // read port B
    always @(*) begin
        case (addr_b)
            2'd0:    data_b = r0;
            2'd1:    data_b = r1;
            2'd2:    data_b = r2;
            default: data_b = r3;
        endcase
    end

endmodule
