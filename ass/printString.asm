;;; printString
;;;
;;; Address of string passed in ZP_PTR1 and ZP_PTR1+1

printString:
    LDY #0
.loop:
    LDA (ZP_PTR1),Y
    BEQ .done        ; Null-terminator check
    JSR CHROUT
    INY
    BNE .loop        ; Keep printing if not wrapped Y
    INC ZP_PTR1+1     ; Handle page crossing
    JMP .loop
.done:
    RTS

	
