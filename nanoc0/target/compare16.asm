;;; Nano C target helper: 16-bit comparisons.
;;; Left operand is in A/X, right operand in NC_TMP, result is C 0/1 in A/X.
;;; Y and flags are scratch; NC_TMP is unchanged.

__nc_eq16:
	cmp NC_TMP
	bne .false
	cpx NC_TMP+1
	bne .false
	lda #$01
	ldx #$00
	rts
.false:
	lda #$00
	tax
	rts

__nc_ne16:
	cmp NC_TMP
	bne .true
	cpx NC_TMP+1
	bne .true
	lda #$00
	tax
	rts
.true:
	lda #$01
	ldx #$00
	rts

;;; Unsigned comparisons inspect the high byte first. A remains the left low
;;; byte while CPX compares the high bytes, so the equal-high case falls straight
;;; into the low-byte CMP.
__nc_ult16:
	cpx NC_TMP+1
	bcc .true
	bne .false
	cmp NC_TMP
	bcc .true
.false:
	lda #$00
	tax
	rts
.true:
	lda #$01
	ldx #$00
	rts

__nc_ule16:
	cpx NC_TMP+1
	bcc .true
	bne .false
	cmp NC_TMP
	bcc .true
	beq .true
.false:
	lda #$00
	tax
	rts
.true:
	lda #$01
	ldx #$00
	rts

__nc_ugt16:
	cpx NC_TMP+1
	bcc .false
	bne .true
	cmp NC_TMP
	bcc .false
	beq .false
.true:
	lda #$01
	ldx #$00
	rts
.false:
	lda #$00
	tax
	rts

__nc_uge16:
	cpx NC_TMP+1
	bcc .false
	bne .true
	cmp NC_TMP
	bcc .false
.true:
	lda #$01
	ldx #$00
	rts
.false:
	lda #$00
	tax
	rts

;;; Signed comparisons need special handling only when the sign bits differ.
;;; TAY preserves the left low byte while A checks the two high-byte signs. If
;;; the signs match, the corresponding unsigned comparison is exactly right for
;;; two's-complement values.
__nc_slt16:
	tay
	txa
	eor NC_TMP+1
	bpl .sameSign
	txa
	bmi .true
	lda #$00
	tax
	rts
.true:
	lda #$01
	ldx #$00
	rts
.sameSign:
	tya
	jmp __nc_ult16

__nc_sle16:
	tay
	txa
	eor NC_TMP+1
	bpl .sameSign
	txa
	bmi .true
	lda #$00
	tax
	rts
.true:
	lda #$01
	ldx #$00
	rts
.sameSign:
	tya
	jmp __nc_ule16

__nc_sgt16:
	tay
	txa
	eor NC_TMP+1
	bpl .sameSign
	txa
	bmi .false
	lda #$01
	ldx #$00
	rts
.false:
	lda #$00
	tax
	rts
.sameSign:
	tya
	jmp __nc_ugt16

__nc_sge16:
	tay
	txa
	eor NC_TMP+1
	bpl .sameSign
	txa
	bmi .false
	lda #$01
	ldx #$00
	rts
.false:
	lda #$00
	tax
	rts
.sameSign:
	tya
	jmp __nc_uge16
