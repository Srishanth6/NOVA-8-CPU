; smoke.asm - quick whole-CPU test (same program as the step 7 smoke test)
; Expected at HLT: R0=08 R1=01 R2=05 R3=00, RAM[10]=08, ZCNV=1000

        LDI  R0, 0x05
        LDI  R1, 0x03
        ADD  R0, R1         ; R0 = 8
        ST   R0, 0x10       ; RAM[10] = 8
        LD   R2, 0x10       ; R2 = 8
        SUB  R2, R1         ; R2 = 5
        MOV  R3, R2         ; R3 = 5
        LDI  R1, 0x01
loop:   SUB  R3, R1         ; R3 = R3 - 1
        BRNZ loop
        JMP  done
        LDI  R0, 0xEE       ; skipped by the JMP
done:   HLT
