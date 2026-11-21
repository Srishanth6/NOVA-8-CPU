# NOVA-8 instruction set (v1)

## Format

Every instruction is one 16-bit word:

```
 15    12 11  10 9    8 7               0
+--------+------+------+-----------------+
| opcode |  rd  |  rs  |  imm8 / address |
+--------+------+------+-----------------+
```

Unused fields are reserved and must be 0 (the assembler always writes 0; the
hardware ignores them). For branches the `rs` field holds the condition.

## Instructions

| Op  | Mnemonic        | Operation              | Flags   | Encoding example |
|-----|-----------------|------------------------|---------|------------------|
| 0x0 | `NOP`           | nothing                | -       | `NOP` = 0000 |
| 0x1 | `MOV rd, rs`    | rd = rs                | -       | `MOV R3, R2` = 1E00 |
| 0x2 | `LDI rd, imm`   | rd = imm8              | -       | `LDI R1, 0x03` = 2403 |
| 0x3 | `ADD rd, rs`    | rd = rd + rs           | Z C N V | `ADD R0, R1` = 3100 |
| 0x4 | `SUB rd, rs`    | rd = rd - rs           | Z C N V | `SUB R2, R1` = 4900 |
| 0x5 | `AND rd, rs`    | rd = rd & rs           | Z N     | `AND R0, R0` = 5000 |
| 0x6 | `OR rd, rs`     | rd = rd \| rs          | Z N     | `OR R2, R1` = 6900 |
| 0x7 | `XOR rd, rs`    | rd = rd ^ rs           | Z N     | `XOR R2, R1` = 7900 |
| 0x8 | `NOT rd`        | rd = ~rd               | Z N     | `NOT R2` = 8800 |
| 0x9 | `SHL rd`        | rd = rd << 1           | Z C N   | `SHL R2` = 9800 |
| 0xA | `SHR rd`        | rd = rd >> 1 (logical) | Z C N   | `SHR R0` = A000 |
| 0xB | `LD rd, addr`   | rd = RAM[addr]         | -       | `LD R2, 0x10` = B810 |
| 0xC | `ST rd, addr`   | RAM[addr] = rd         | -       | `ST R0, 0x10` = C010 |
| 0xD | `JMP addr`      | PC = addr              | -       | `JMP 0x0C` = D00C |
| 0xE | `BRZ/BRC/BRN/BRNZ addr` | if cond: PC = addr | - | `BRNZ 0x08` = E308 |
| 0xF | `HLT`           | stop (HALT state)      | -       | `HLT` = F000 |

### Branch conditions (rs field)

| rs | Mnemonic | `BR cond, addr` | Taken when |
|----|----------|-----------------|-----------|
| 00 | `BRZ`    | `BR 0` or `BR Z`  | Z = 1 |
| 01 | `BRC`    | `BR 1` or `BR C`  | C = 1 |
| 10 | `BRN`    | `BR 2` or `BR N`  | N = 1 |
| 11 | `BRNZ`   | `BR 3` or `BR NZ` | Z = 0 |

## Flags

| Flag | Meaning |
|------|---------|
| Z | result is 0x00 |
| C | ADD: carry out of bit 7. SUB: borrow (1 when rd < rs unsigned). SHL: old bit 7. SHR: old bit 0. |
| N | bit 7 of the result |
| V | signed overflow (ADD and SUB only) |

Careful with C after SUB: C = 1 means a borrow happened (rd < rs unsigned).
That is the opposite of the 6502 and ARM convention, where C = 1 after a
subtract means *no* borrow. So `BRC` after `SUB` branches when rd < rs.

Only ALU instructions (0x3 to 0xA) write the flags, and they only change the
flags listed in the table; the others keep their old value. For example AND
keeps C and V, and SHL keeps V. MOV, LDI, LD and the rest never touch the flags.
All flags are 0 after reset.

Edge cases (all checked in `tb/tb_alu.v`):

| Operation    | Result | Z C N V |
|--------------|--------|---------|
| 127 + 1      | 0x80   | 0 0 1 1 |
| 255 + 1      | 0x00   | 1 1 0 0 |
| 0 - 1        | 0xFF   | 0 1 1 0 |
| -128 - 1     | 0x7F   | 0 0 0 1 |

## Assembler syntax (`assembler.py`)

```
; comment (// also works)
label:  LDI  R0, 10        ; decimal
        LDI  R1, 0x0F      ; hex
        LDI  R2, 0b1010    ; binary
        LDI  R3, -1        ; negative -> two's complement (0xFF), LDI only
loop:   SUB  R0, R1
        BRNZ loop          ; labels work for JMP and all branches
        BR   3, loop       ; same thing, raw condition code
        BR   NZ, loop      ; same thing, condition name (Z, C, N, NZ)
        HLT
```

- Mnemonics, register names and condition names are case-insensitive.
  Labels are case-sensitive: `loop` and `Loop` are different labels.
- A label can be on its own line or in front of an instruction. It can't
  have the name of a register (`R0`-`R3`) or an instruction (`ADD`, `BR`,
  `BRZ`, ...), in any case.
- Numbers: decimal (`10`; a leading zero like `010` is still decimal 10),
  hex (`0x1F`) or binary (`0b1010`). Nothing else (no `_`, no `0o`, no `+`).
- Only the LDI immediate can be negative (-128 to 255). Addresses for LD,
  ST, JMP and branches must be 0 to 255, and a label used as an address must
  be inside the ROM (a label after the 256th word is an error).
- The output `.hex` always has 256 words: the program, then `0000` (NOP)
  padding. Each instruction line keeps its address and source as a comment.
- Errors (bad register, unknown label, value out of range, wrong operand
  count, reserved label name) stop the assembler with the line number and a
  non-zero exit code.
- A program without `HLT` assembles, but with a warning: the CPU would run
  through the NOP padding and wrap around to address 0.
