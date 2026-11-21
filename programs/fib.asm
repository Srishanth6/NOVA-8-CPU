; fib.asm - Fibonacci numbers, F(13) = 233 is the largest that fits in 8 bits
;
; (a, b) starts as (F0, F1) = (0, 1); after k passes it is (Fk, Fk+1).
; 12 passes leave a = F12 = 144 (0x90), b = F13 = 233 (0xE9).
; Expected at HLT: R0=90 R1=E9 R2=00 R3=01, RAM[40]=E9 RAM[41]=90, ZCNV=1000

        LDI  R0, 0          ; a
        LDI  R1, 1          ; b
        LDI  R2, 12         ; passes left
loop:   MOV  R3, R0
        ADD  R3, R1         ; t = a + b
        MOV  R0, R1         ; a = b
        MOV  R1, R3         ; b = t
        LDI  R3, 1          ; R3 reused as the constant 1
        SUB  R2, R3         ; passes--
        BRNZ loop
        ST   R1, 0x40       ; F13
        ST   R0, 0x41       ; F12
        HLT
