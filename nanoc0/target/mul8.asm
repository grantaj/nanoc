;;; Nano C target helper: low byte of an 8-bit multiply.
;;; Left operand is in NC_TMP, right operand in A, low-byte result in A.
;;;
;;; Eight fixed shift/add steps are deliberately simpler than a second 16-bit
;;; protocol. Overflow is discarded exactly as a char consumer requires.

__nc_mul8:
	cld
	sta NC_PTR
	lda #$00
	ldx #$08
.loop:
	lsr NC_PTR
	bcc .noadd
	clc
	adc NC_TMP
.noadd:
	asl NC_TMP
	dex
	bne .loop
	rts
