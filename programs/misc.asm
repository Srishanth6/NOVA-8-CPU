; misc.asm - things no other program covers: NOP, a backwards JMP,
; NOT flags, SHL carry/negative, an LD/ST round trip, and V staying set
; through logic ops
;
; Same style as branch.asm: the correct path stores 01 (pass) to the
; test's RAM address, the wrong path stores EE.
;
; Flags (ZCNV) after each flag-setting instruction, from reset = 0000:
;   T1 NOT FF -> 00          1000   BRZ taken
;   T2 NOT 00 -> FF          0010   BRN taken, T3 BRZ not taken
;   T4 SHL 81 -> 02 (C out)  0100   BRC taken, T5 BRN not taken
;   T6 SHL 40 -> 80          0010   BRN taken, T7 BRC not taken
;   T8 SUB 5A - 5A -> 00     1000   BRZ taken
;   T9 ADD 7F + 01 -> 80     0011   V set
;      AND 80 & 80 -> 80     0011   C and V kept
;      OR  80 | 01 -> 81     0011
;      XOR 81 ^ 01 -> 80     0011
;      NOT 80 -> 7F          0001   only V left
;
; RAM writes in order: 80..87 = 01, 90 = 5A, 91 = 5A, 88 = 01, 89 = 7F
; Expected at HLT: RAM[80..88] = 01, RAM[89] = 7F, RAM[90] = RAM[91] = 5A,
;                  R0=7F R1=01 R2=01 R3=EE, ZCNV=0001, PC=40 (HLT at 3F)
;
; Cycles: prologue 24 (NOP 2, LDI 4, LDI 4, NOP 2, JMP 3, JMP 3, ST 3, JMP 3),
; T1 14, T2 10, T3 9, T4 14, T5 9, T6 14, T7 9, T8 32, T9 31, HLT 2 = 168

        NOP
        LDI  R2, 0x01       ; pass marker
        LDI  R3, 0xEE       ; fail marker
        NOP
        JMP  start

; T0 (80): only reachable through the JMP backwards below
back:   ST   R2, 0x80
        JMP  t1
start:  JMP  back
        ST   R3, 0x80       ; backwards JMP not taken

; T1 (81): NOT 0xFF = 0x00 -> Z=1, BRZ taken
t1:     LDI  R0, 0xFF
        NOT  R0
        BRZ  t1_ok
        ST   R3, 0x81
        JMP  t2
t1_ok:  ST   R2, 0x81

; T2 (82): NOT 0x00 = 0xFF -> N=1, BRN taken
t2:     NOT  R0
        BRN  t2_ok
        ST   R3, 0x82
        JMP  t3
t2_ok:  ST   R2, 0x82

; T3 (83): Z=0 after the NOT, BRZ not taken
t3:     BRZ  t3_bad
        ST   R2, 0x83
        JMP  t4
t3_bad: ST   R3, 0x83

; T4 (84): SHL 0x81 = 0x02, bit 7 goes to C, BRC taken
t4:     LDI  R0, 0x81
        SHL  R0
        BRC  t4_ok
        ST   R3, 0x84
        JMP  t5
t4_ok:  ST   R2, 0x84

; T5 (85): 0x02 is positive, BRN not taken
t5:     BRN  t5_bad
        ST   R2, 0x85
        JMP  t6
t5_bad: ST   R3, 0x85

; T6 (86): SHL 0x40 = 0x80 -> N=1, BRN taken
t6:     LDI  R0, 0x40
        SHL  R0
        BRN  t6_ok
        ST   R3, 0x86
        JMP  t7
t6_ok:  ST   R2, 0x86

; T7 (87): bit 7 of 0x40 was 0, so C=0, BRC not taken
t7:     BRC  t7_bad
        ST   R2, 0x87
        JMP  t8
t7_bad: ST   R3, 0x87

; T8 (88): store 0x5A, clobber R0, load it back, copy it to 0x91
t8:     LDI  R0, 0x5A
        ST   R0, 0x90
        LDI  R0, 0x00
        LD   R0, 0x90
        ST   R0, 0x91
        LDI  R1, 0x5A
        SUB  R0, R1         ; 0 if the round trip worked
        BRZ  t8_ok
        ST   R3, 0x88
        JMP  t9
t8_ok:  ST   R2, 0x88

; T9 (89): V from the ADD survives AND, OR, XOR and NOT (checked in the
; final flags, there is no branch on V)
t9:     LDI  R1, 0x01
        LDI  R0, 0x7F
        ADD  R0, R1
        AND  R0, R0
        OR   R0, R1
        XOR  R0, R1
        NOT  R0
        ST   R0, 0x89

        HLT
