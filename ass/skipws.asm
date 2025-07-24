;;; skipWhiteSpacxe
;;; Pointer to string at $FE (L), $FF (H)
;;; Advances pointer to first non whitespace character
;;;
;;; whitespace characters: SPC, TAB
;;;
;;; A, X, Y preserved

STRLO = $fe
STRHI = $ff
	
skipWitespace:
	pha
	tya
	pha

	ldy #0

.loop:

	lda (STRLO),Y
	cmp #' '         	; space
	beq .inc
	cmp #$09         	; tab
	beq .inc

	;; non whitespace found
	
	pla			; restore A and Y
	tay
	pla
	
	rts             	

.inc:
	
	inc STRLO
	bne .loop
	inc STRHI
	jmp .loop
