; countdown.asm - count R0 down from 10 to 0, counting the loop passes in R2
; Expected at HLT: R0=00 R1=01 R2=0A R3=00, RAM[30]=0A RAM[31]=00, ZCNV=1000

        LDI  R0, 10         ; counter
        LDI  R1, 1          ; constant 1
        LDI  R2, 0          ; loop passes
loop:   ADD  R2, R1         ; passes++
        SUB  R0, R1         ; counter--
        BRNZ loop           ; until counter == 0
        ST   R2, 0x30
        ST   R0, 0x31
        HLT
