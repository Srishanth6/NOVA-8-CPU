; arith.asm - every ALU operation once, results stored to RAM 0x20-0x28
;
; R0 = 0x3C (0011 1100), R1 = 0x0F (0000 1111)
; Expected RAM:
;   20: ADD 4B   21: SUB 2D   22: AND 0C   23: OR  3F   24: XOR 33
;   25: NOT C3   26: SHL 78   27: SHR 1E   28: 4B + 2D = 78 (via LD)
; Expected at HLT: R0=3C R1=0F R2=2D R3=78, ZCNV=0000

        LDI  R0, 0x3C
        LDI  R1, 0x0F

        MOV  R2, R0
        ADD  R2, R1         ; 3C + 0F = 4B
        ST   R2, 0x20

        MOV  R2, R0
        SUB  R2, R1         ; 3C - 0F = 2D
        ST   R2, 0x21

        MOV  R2, R0
        AND  R2, R1         ; 0C
        ST   R2, 0x22

        MOV  R2, R0
        OR   R2, R1         ; 3F
        ST   R2, 0x23

        MOV  R2, R0
        XOR  R2, R1         ; 33
        ST   R2, 0x24

        MOV  R2, R0
        NOT  R2             ; C3
        ST   R2, 0x25

        MOV  R2, R0
        SHL  R2             ; 78
        ST   R2, 0x26

        MOV  R2, R0
        SHR  R2             ; 1E
        ST   R2, 0x27

        ; read two results back from RAM and add them
        LD   R3, 0x20       ; 4B
        LD   R2, 0x21       ; 2D
        ADD  R3, R2         ; 78
        ST   R3, 0x28

        HLT
