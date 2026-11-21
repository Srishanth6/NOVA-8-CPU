#!/usr/bin/env python3
"""NOVA-8 assembler: turns a .asm file into a hex file for $readmemh.

Usage:
    python assembler.py programs/fib.asm              -> programs/fib.hex
    python assembler.py programs/fib.asm -o out.hex

Syntax (one instruction per line):
    label:  LDI  R0, 0x10     ; comment (// also works)
            ADD  R0, R1
            BRNZ label

Mnemonics and register names are case-insensitive, labels are
case-sensitive (loop and Loop are two different labels). A label can't be
named like a register (R0-R3) or an instruction (ADD, BRZ, ...).

Numbers: decimal (10, 010 is also decimal 10), hex (0x1F) or binary
(0b1010). Only LDI takes negative numbers (-128 to -1 become two's
complement); addresses for LD, ST, JMP and branches must be 0-255.

Branches: BRZ, BRC, BRN, BRNZ addr, or BR cond, addr with cond 0-3 or
Z, C, N, NZ.

The output always has 256 words (padded with 0000 = NOP) and every
instruction line has the address and source as a // comment. A program
without HLT gets a warning, because the CPU would run on through the
padding and wrap around to address 0.
"""

import argparse
import re
import sys

ROM_SIZE = 256

# mnemonic -> (opcode, operand format)
#   ""    no operands
#   "rd"  one register
#   "rr"  rd, rs
#   "ri"  rd, imm8 (LDI, may be negative)
#   "ra"  rd, address
#   "a"   address only
#   "ca"  branch condition, address
OPCODES = {
    "NOP": (0x0, ""),
    "MOV": (0x1, "rr"),
    "LDI": (0x2, "ri"),
    "ADD": (0x3, "rr"),
    "SUB": (0x4, "rr"),
    "AND": (0x5, "rr"),
    "OR":  (0x6, "rr"),
    "XOR": (0x7, "rr"),
    "NOT": (0x8, "rd"),
    "SHL": (0x9, "rd"),
    "SHR": (0xA, "rd"),
    "LD":  (0xB, "ra"),
    "ST":  (0xC, "ra"),
    "JMP": (0xD, "a"),
    "BR":  (0xE, "ca"),
    "HLT": (0xF, ""),
}

NUM_OPERANDS = {"": 0, "rd": 1, "rr": 2, "ri": 2, "ra": 2, "a": 1, "ca": 2}

# branch aliases -> condition code in the rs field
BRANCHES = {"BRZ": 0, "BRC": 1, "BRN": 2, "BRNZ": 3}

# condition names allowed in "BR cond, addr"
COND_NAMES = {"Z": 0, "C": 1, "N": 2, "NZ": 3}

LABEL_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
REG_RE = re.compile(r"^[Rr]([0-3])$")
NUM_RE = re.compile(r"^(-?)(0[xX][0-9A-Fa-f]+|0[bB][01]+|[0-9]+)$")


class AsmError(Exception):
    pass


def parse_reg(text):
    m = REG_RE.match(text)
    if not m:
        raise AsmError(f"bad register '{text}' (use R0-R3)")
    return int(m.group(1))


def parse_number(text):
    """Number literal -> int, or None if text is not a number."""
    m = NUM_RE.match(text)
    if not m:
        return None
    sign, digits = m.groups()
    if digits[:2] in ("0x", "0X"):
        value = int(digits[2:], 16)
    elif digits[:2] in ("0b", "0B"):
        value = int(digits[2:], 2)
    else:
        value = int(digits, 10)
    return -value if sign else value


def parse_value(text, labels, allow_negative):
    """Number or label -> 8-bit field value.

    allow_negative is only True for the LDI immediate. Everything is
    range-checked before it is masked to 8 bits.
    """
    value = parse_number(text)
    if value is not None:
        if text.startswith("-") and not allow_negative:
            raise AsmError(f"negative address '{text}' (addresses are 0-255)")
        low = -128 if allow_negative else 0
        if value < low or value > 255:
            raise AsmError(f"value {text} does not fit in 8 bits ({low} to 255)")
        return value & 0xFF

    if REG_RE.match(text):
        raise AsmError(f"expected a number or label, got register '{text}'")
    if not LABEL_RE.match(text):
        raise AsmError(f"bad number or label '{text}'")
    if text not in labels:
        raise AsmError(f"unknown label '{text}' (labels are case-sensitive)")
    value = labels[text]
    if value > 255:
        raise AsmError(f"label '{text}' is at address {value}, outside the ROM (0-255)")
    return value


def parse_cond(text):
    if text.upper() in COND_NAMES:
        return COND_NAMES[text.upper()]
    value = parse_number(text)
    if value is None or value < 0 or value > 3:
        raise AsmError(f"branch condition must be 0-3 or Z, C, N, NZ, got '{text}'")
    return value


def reserved_kind(name):
    """'register' / 'instruction' if name can't be used as a label, else None."""
    if REG_RE.match(name):
        return "register"
    if name.upper() in OPCODES or name.upper() in BRANCHES:
        return "instruction"
    return None


def strip_comment(line):
    return line.split(";", 1)[0].split("//", 1)[0].strip()


def first_pass(lines):
    """Collect labels and the list of (line number, address, instruction text)."""
    labels = {}
    instrs = []
    addr = 0
    for num, raw in enumerate(lines, start=1):
        line = strip_comment(raw)
        # a line can have a label, an instruction, or both
        while ":" in line:
            name, line = line.split(":", 1)
            name = name.strip()
            line = line.strip()
            if not LABEL_RE.match(name):
                raise AsmError(f"line {num}: bad label '{name}'")
            kind = reserved_kind(name)
            if kind:
                raise AsmError(f"line {num}: label '{name}' has the same name as "
                               f"a{'n' if kind == 'instruction' else ''} {kind}")
            if name in labels:
                raise AsmError(f"line {num}: label '{name}' defined twice")
            labels[name] = addr
        if line:
            if addr >= ROM_SIZE:
                raise AsmError(f"line {num}: program is longer than {ROM_SIZE} words")
            instrs.append((num, addr, line))
            addr += 1
    return labels, instrs


def encode(text, labels):
    parts = text.split(None, 1)
    written = parts[0]
    mnem = written.upper()
    ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []

    if mnem in BRANCHES:
        cond = BRANCHES[mnem]
        fmt_ops = 1
    elif mnem in OPCODES:
        fmt_ops = NUM_OPERANDS[OPCODES[mnem][1]]
    else:
        raise AsmError(f"unknown instruction '{written}'")

    if len(ops) != fmt_ops:
        raise AsmError(f"{written} needs {fmt_ops} operand(s), got {len(ops)}")
    if "" in ops:
        raise AsmError(f"{written}: empty operand")

    if mnem in BRANCHES:
        ops = [str(cond)] + ops
        mnem = "BR"

    opcode, fmt = OPCODES[mnem]
    rd = rs = imm = 0
    if fmt == "rd":
        rd = parse_reg(ops[0])
    elif fmt == "rr":
        rd, rs = parse_reg(ops[0]), parse_reg(ops[1])
    elif fmt == "ri":
        rd, imm = parse_reg(ops[0]), parse_value(ops[1], labels, True)
    elif fmt == "ra":
        rd, imm = parse_reg(ops[0]), parse_value(ops[1], labels, False)
    elif fmt == "a":
        imm = parse_value(ops[0], labels, False)
    elif fmt == "ca":
        rs = parse_cond(ops[0])
        imm = parse_value(ops[1], labels, False)

    return (opcode << 12) | (rd << 10) | (rs << 8) | imm


def assemble(lines):
    """Return a list of (address, word, source text)."""
    labels, instrs = first_pass(lines)
    out = []
    for num, addr, text in instrs:
        try:
            out.append((addr, encode(text, labels), text))
        except AsmError as e:
            raise AsmError(f"line {num}: {e}")
    return out


def write_hex(path, program, src_name):
    used = {addr for addr, _, _ in program}
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"// assembled from {src_name} by assembler.py, do not edit\n")
        f.write("// hex    addr  source\n")
        for addr, word, text in program:
            f.write(f"{word:04X}    // {addr:02X}  {text}\n")
        for addr in range(ROM_SIZE):
            if addr not in used:
                f.write("0000\n")


def main():
    ap = argparse.ArgumentParser(description="NOVA-8 assembler")
    ap.add_argument("source", help=".asm file")
    ap.add_argument("-o", "--output", help="output .hex (default: same name as source)")
    args = ap.parse_args()

    out_path = args.output or re.sub(r"\.asm$", "", args.source, flags=re.IGNORECASE) + ".hex"
    try:
        with open(args.source, encoding="utf-8") as f:
            program = assemble(f.readlines())
    except UnicodeDecodeError:
        print(f"error: {args.source}: not a UTF-8 text file", file=sys.stderr)
        sys.exit(1)
    except (OSError, AsmError) as e:
        print(f"error: {args.source}: {e}", file=sys.stderr)
        sys.exit(1)

    if not any(word >> 12 == 0xF for _, word, _ in program):
        print(f"warning: {args.source}: no HLT, the CPU will run through the "
              f"NOP padding and wrap around to address 0", file=sys.stderr)

    write_hex(out_path, program, args.source.replace("\\", "/"))
    print(f"{args.source}: {len(program)} words -> {out_path}")


if __name__ == "__main__":
    main()
