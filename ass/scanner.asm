;;; scanner.asm
;;;
;;; Small source-scanning helpers. Source text is never copied.
;;;
;;; sourceEnd contains the address one byte past the source buffer.

;;; sourceAtEnd
;;;
;;; Returns Z set when ZP_PTR1 == sourceEnd, clear otherwise.
;;; A and flags are clobbered. X and Y are preserved.
sourceAtEnd:
	lda ZP_PTR1
	cmp sourceEnd
	bne .notEnd
	lda ZP_PTR1+1
	cmp sourceEnd+1
	rts
.notEnd:
	lda #$01
	rts

;;; advanceSource
;;;
;;; Advances ZP_PTR1 by one byte.
;;; Registers are preserved. Flags are clobbered.
advanceSource:
	inc ZP_PTR1
	bne .done
	inc ZP_PTR1+1
.done:
	rts

;;; scanLexeme
;;;
;;; ZP_PTR1 points to the first byte of a lexeme.
;;; Returns ZP_PTR0 pointing to that same byte and X containing its length.
;;; ZP_PTR1 is advanced to the first space, tab, NUL, or sourceEnd.
;;; No source bytes are modified or copied.
;;;
;;; A, X, Y and flags are clobbered.
scanLexeme:
	lda ZP_PTR1
	sta ZP_PTR0
	lda ZP_PTR1+1
	sta ZP_PTR0+1
	ldx #$00
	ldy #$00

.loop:
	jsr sourceAtEnd
	beq .done

	lda (ZP_PTR1),y
	beq .done
	cmp #' '
	beq .done
	cmp #$09
	beq .done

	inx
	jsr advanceSource
	jmp .loop

.done:
	rts
