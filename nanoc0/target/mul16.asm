;;; Nano C target helpers: low-byte and 16-bit multiply.
;;;
;;; A byte consumer needs only the product modulo 256. That is a physical
;;; machine fact, independent of the promoted C expression type: the low byte of
;;; a product depends only on the low bytes of its operands.

;;; Left operand is in NC_TMP, right operand in A, low-byte result in A.
__nc_mul8:
	cld
	sta NC_PTR
	ldy #$00
.loop:
	lda NC_PTR
	beq .done
	and #$01
	beq .noadd
	tya
	clc
	adc NC_TMP
	tay
.noadd:
	asl NC_TMP
	lsr NC_PTR
	jmp .loop
.done:
	tya
	cld
	rts

;;; Left operand is in NC_TMP, right operand in A/X, low 16-bit result in A/X.
__nc_mul16:
	cld
	sta NC_PTR
	stx NC_PTR+1
	ldy #$00
	ldx #$00
.loop:
	lda NC_PTR
	ora NC_PTR+1
	beq .done
	lda NC_PTR
	and #$01
	beq .noadd
	tya
	clc
	adc NC_TMP
	tay
	txa
	adc NC_TMP+1
	tax
.noadd:
	asl NC_TMP
	rol NC_TMP+1
	lsr NC_PTR+1
	ror NC_PTR
	jmp .loop
.done:
	tya
	cld
	rts
