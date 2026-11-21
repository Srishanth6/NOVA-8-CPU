; branch.asm - flag and branch tests
;
; Each test sets the flags with an ALU op and then branches. The correct
; path stores 01 (pass) to the test's RAM address, the wrong path stores EE.
; Expected at HLT: RAM[50..5A] all 01, R0=7F R1=01 R2=01 R3=EE, ZCNV=0001
; (the final ZCNV=0001 also checks the V flag, which has no branch)

        LDI  R2, 0x01       ; pass marker
        LDI  R3, 0xEE       ; fail marker
        LDI  R1, 0x01

; T0 (50): 127 + 1 = 0x80 -> ZCNV=0011, BRN taken
        LDI  R0, 0x7F
        ADD  R0, R1
        BRN  t0_ok
        ST   R3, 0x50
        JMP  t1
t0_ok:  ST   R2, 0x50

; T1 (51): Z=0, so BRZ not taken
t1:     BRZ  t1_bad
        ST   R2, 0x51
        JMP  t2
t1_bad: ST   R3, 0x51

; T2 (52): 255 + 1 = 0x00 -> ZCNV=1100, BRC taken
t2:     LDI  R0, 0xFF
        ADD  R0, R1
        BRC  t2_ok
        ST   R3, 0x52
        JMP  t3
t2_ok:  ST   R2, 0x52

; T3 (53): Z=1, BRZ taken
t3:     BRZ  t3_ok
        ST   R3, 0x53
        JMP  t4
t3_ok:  ST   R2, 0x53

; T4 (54): Z=1, BRNZ not taken
t4:     BRNZ t4_bad
        ST   R2, 0x54
        JMP  t5
t4_bad: ST   R3, 0x54

; T5 (55): 0 - 1 = 0xFF -> borrow, ZCNV=0110, BRC taken
t5:     LDI  R0, 0x00
        SUB  R0, R1
        BRC  t5_ok
        ST   R3, 0x55
        JMP  t6
t5_ok:  ST   R2, 0x55

; T6 (56): AND keeps C, so C is still 1 from the SUB
t6:     AND  R0, R0         ; 0xFF -> ZCNV=0110
        BRC  t6_ok
        ST   R3, 0x56
        JMP  t7
t6_ok:  ST   R2, 0x56

; T7 (57): LDI does not touch flags, Z stays 0 even though R0 = 0
t7:     LDI  R0, 0x00
        BRZ  t7_bad
        ST   R2, 0x57
        JMP  t8
t7_bad: ST   R3, 0x57

; T8 (58): SHR 0x01 = 0x00 -> ZCNV=1100, BRC taken
t8:     LDI  R0, 0x01
        SHR  R0
        BRC  t8_ok
        ST   R3, 0x58
        JMP  t9
t8_ok:  ST   R2, 0x58

; T9 (59): -128 - 1 = 0x7F -> ZCNV=0001 (overflow), BRN not taken
t9:     LDI  R0, 0x80
        SUB  R0, R1
        BRN  t9_bad
        ST   R2, 0x59
        JMP  t10
t9_bad: ST   R3, 0x59

; T10 (5A): Z=0, BRNZ taken
t10:    BRNZ t10_ok
        ST   R3, 0x5A
        JMP  done
t10_ok: ST   R2, 0x5A

done:   HLT
