; memcopy.asm - fill 8 bytes at 0x60-0x67, then copy them to 0x70-0x77
;
; NOVA-8 v1 only has absolute addresses (no pointer register), so the
; copy has to be unrolled: one LD/ST pair per byte.
;
; Data: DE AD BE EF 01 80 7F 00
; Expected at HLT: RAM[60..67] = RAM[70..77] = data, R0=00 R1=00, ZCNV=0000

        ; fill the source block
        LDI  R0, 0xDE
        ST   R0, 0x60
        LDI  R0, 0xAD
        ST   R0, 0x61
        LDI  R0, 0xBE
        ST   R0, 0x62
        LDI  R0, 0xEF
        ST   R0, 0x63
        LDI  R0, 0x01
        ST   R0, 0x64
        LDI  R0, 0x80
        ST   R0, 0x65
        LDI  R0, 0x7F
        ST   R0, 0x66
        LDI  R0, 0x00
        ST   R0, 0x67

        ; copy 0x60-0x67 -> 0x70-0x77
        LD   R1, 0x60
        ST   R1, 0x70
        LD   R1, 0x61
        ST   R1, 0x71
        LD   R1, 0x62
        ST   R1, 0x72
        LD   R1, 0x63
        ST   R1, 0x73
        LD   R1, 0x64
        ST   R1, 0x74
        LD   R1, 0x65
        ST   R1, 0x75
        LD   R1, 0x66
        ST   R1, 0x76
        LD   R1, 0x67
        ST   R1, 0x77

        HLT
