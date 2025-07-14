* = $c000

start:
        lda #$00
loop:
        sta $d020
        clc
        adc #$01
        jmp loop
