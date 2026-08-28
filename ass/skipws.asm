;;; skipWhitespace
;;;
;;; ZP_PTR1 points to source text.
;;; Advances it to the first non-space/non-tab byte.
;;;
;;; A, Y and flags are clobbered. X is preserved.
skipWhitespace:
	ldy #$00

.loop:
	lda (ZP_PTR1),y
	cmp #' '
	beq .advance
	cmp #$09
	beq .advance
	rts

.advance:
	inc ZP_PTR1
	bne .loop
	inc ZP_PTR1+1
	jmp .loop
