`timescale 1ns/1ps

// NOVA-8 top level: connects the datapath and the control unit.
//
// Datapath:
//   ROM[PC] -> IR -> fields (opcode, rd, rs, imm8)
//   reg file port A = rd, port B = rs
//   ALU a = R[rd], b = R[rs] or imm8 (LDI)
//   EXECUTE latches the ALU result in alu_out (and the flags for ALU ops)
//   MEMORY  uses imm8 as the RAM address: LD latches RAM data in mdr,
//           ST writes R[rd] to RAM
//   WRITEBACK writes alu_out or mdr into rd
//   JMP / BR load imm8 into the PC
//
// The RAM write bus is brought out as outputs so synthesis can't
// optimise the datapath away.

module nova8_top #(
    parameter PROG_FILE = "programs/program.hex"
) (
    input  wire       clk,
    input  wire       rst,
    output wire       halted,
    output wire [7:0] pc_out,
    output wire       ram_we,
    output wire [7:0] ram_addr,
    output wire [7:0] ram_wdata
);

    // control signals
    wire [2:0] state;
    wire       ir_load, pc_inc, pc_load, reg_we, flags_we;
    wire       alu_load, mem_we, mdr_load, alu_b_sel, wb_sel;

    // datapath wires
    wire [15:0] rom_data;
    wire [15:0] ir_out;
    wire [3:0]  opcode;
    wire [1:0]  rd, rs;
    wire [7:0]  imm8;
    wire [7:0]  rd_val, rs_val;
    wire [7:0]  alu_b, alu_result;
    wire [3:0]  alu_flags;
    wire [7:0]  ram_rdata;
    wire [7:0]  wb_data;

    // small internal registers
    reg  [3:0]  flags;    // {Z, C, N, V}
    reg  [7:0]  alu_out;  // ALU result, held for WRITEBACK
    reg  [7:0]  mdr;      // memory data register, held for WRITEBACK

    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .pc_load (pc_load),
        .pc_inc  (pc_inc),
        .pc_in   (imm8),
        .pc_out  (pc_out)
    );

    instr_rom #(.INIT_FILE(PROG_FILE)) u_rom (
        .addr (pc_out),
        .data (rom_data)
    );

    ir u_ir (
        .clk     (clk),
        .rst     (rst),
        .ir_load (ir_load),
        .ir_in   (rom_data),
        .ir_out  (ir_out),
        .opcode  (opcode),
        .rd      (rd),
        .rs      (rs),
        .imm8    (imm8)
    );

    control_unit u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .opcode    (opcode),
        .cond      (rs),
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

    reg_file u_rf (
        .clk    (clk),
        .rst    (rst),
        .w_en   (reg_we),
        .w_addr (rd),
        .w_data (wb_data),
        .addr_a (rd),
        .data_a (rd_val),
        .addr_b (rs),
        .data_b (rs_val)
    );

    assign alu_b = alu_b_sel ? imm8 : rs_val;

    alu u_alu (
        .alu_op    (opcode),
        .a         (rd_val),
        .b         (alu_b),
        .flags_in  (flags),
        .result    (alu_result),
        .flags_out (alu_flags)
    );

    data_ram u_ram (
        .clk    (clk),
        .w_en   (mem_we),
        .addr   (imm8),
        .w_data (rd_val),
        .r_data (ram_rdata)
    );

    always @(posedge clk) begin
        if (rst) begin
            flags   <= 4'b0000;
            alu_out <= 8'h00;
            mdr     <= 8'h00;
        end else begin
            if (flags_we) flags   <= alu_flags;
            if (alu_load) alu_out <= alu_result;
            if (mdr_load) mdr     <= ram_rdata;
        end
    end

    assign wb_data = wb_sel ? mdr : alu_out;

    assign ram_we    = mem_we;
    assign ram_addr  = imm8;
    assign ram_wdata = rd_val;

endmodule
