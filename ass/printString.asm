;;; printString
;;;
;;; Address of string passed in ZP_PTR1 and ZP_PTR1+1
;;; This pointer is preserved
;;; A is clobbered
;;; X, Y preserved

printString:
	lda ZP_PTR1		; save pointer
	pha
	lda ZP_PTR1+1
	pha
	tya			; save Y
	pha
	
	ldy #0
.loop:
	lda (ZP_PTR1),Y
	beq .done        	; Null-terminator check
	jsr CHROUT
	inc ZP_PTR1
	bne .loop        	; Keep printing if not page boundary	
	inc ZP_PTR1+1     	; Handle page crossing
	jmp .loop
.done:
	pla			; restore Y
	tay
	pla			; restore pointer
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1

	rts

	
