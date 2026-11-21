# NOVA-8 v1 synthesis report

Tool: Yosys 0.71, generic gate library (`synth`, no FPGA or ASIC mapping).
Program in ROM: `programs/program.hex` (the smoke test).
Regenerate with `.\run.ps1 report` or `make report`; the raw output is in
`nova8_stat.txt`, `nova8_flat_stat.txt` and `nova8_check.txt`.

Design check: **0 problems** (no latches, no multiple drivers, no undriven wires).

## Cell count per module (hierarchy kept)

| Module         | Cells | Flip-flops | Notes                                   |
|----------------|------:|-----------:|-----------------------------------------|
| `data_ram`     | 4417  | 2048       | 256 x 8 built from flip-flops + read mux |
| `alu`          |  258  |    0       | adder/subtractor, logic, shifts, flags  |
| `reg_file`     |  147  |   32       | 4 x 8 registers, two read muxes         |
| `instr_rom`    |   69  |    0       | constant logic, depends on the program  |
| `control_unit` |   51  |    3       | 6-state FSM, 3-bit state register       |
| `nova8_top`    |   36  |   20       | flags (4), alu_out (8), mdr (8), muxes  |
| `pc`           |   31  |    8       | incrementer + load mux                  |
| `ir`           |   16  |   16       | just flip-flops                         |
| **Total**      | **5025** | **2127** |                                      |

The **CPU core** (everything except the RAM and ROM) is **539 cells**, of which
79 are flip-flops. The **data RAM is 88% of the design**.

## Why the RAM is so big

`data_ram.v` has a combinational read (`assign r_data = mem[addr]`). There is no
RAM block in a generic gate library that reads without a clock, so Yosys builds
the memory out of 2048 enable flip-flops plus a 256-to-1 read multiplexer for each
of the 8 bits (about 2040 `$_MUX_` cells).

Ideas for NOVA-8 Eco:
- a synchronous (registered) read, so a real SRAM macro or FPGA block RAM can be used
- a smaller RAM, since the test programs only use a few dozen addresses

## Flattened design

After `synth -flatten` (started again from the RTL) the whole CPU is
**2388 cells**, 7 of them `$scopeinfo` cells that only keep the module names, so
2381 real gates. It has **591 flip-flops**: the same 79 in the core as above,
plus 512 RAM flip-flops (`$_DFFE_PP_`) instead of 2048.

The count is smaller because the ROM contents are constants. Once the module
boundaries are gone, Yosys propagates them into the rest of the CPU and removes
the logic it can prove is never used, including part of the RAM. How much gets
removed depends on the program in the ROM (this run used the smoke test), so
the flattened number is not a property of the CPU. Use the per-module table
above when comparing with NOVA-8 Eco.

## ROM initialisation bug (found while making this report)

An earlier `instr_rom.v` filled the ROM with zeros in a `for` loop and then
called `$readmemh`. Icarus runs these in order, so simulation was correct, but
Yosys applied the zero fill *after* the file, so the synthesized ROM was all
NOPs (0 cells). The loop is gone; `assembler.py` now pads every hex file to
256 words instead.
