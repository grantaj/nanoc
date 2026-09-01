;;; Nano C target helper: 16-bit comparisons.
;;; Left operand is in A/X, right operand in NC_TMP, result is C 0/1 in A/X.
;;; Every return also leaves Z matching that result: set X first, then load A.
;;; That lets an if/while consume a comparison directly without rebuilding truth
;;; from both result bytes. Y and the other flags are scratch; NC_TMP is unchanged.

__nc_eq16:
	cmp NC_TMP
	bne .false
	cpx NC_TMP+1
	bne .false
	ldx #$00
	lda #$01
	rts
.false:
	ldx #$00
	lda #$00
	rts

__nc_ne16:
	cmp NC_TMP
	bne .true
	cpx NC_TMP+1
	bne .true
	ldx #$00
	lda #$00
	rts
.true:
	ldx #$00
	lda #$01
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
	ldx #$00
	lda #$00
	rts
.true:
	ldx #$00
	lda #$01
	rts

__nc_ule16:
	cpx NC_TMP+1
	bcc .true
	bne .false
	cmp NC_TMP
	bcc .true
	beq .true
.false:
	ldx #$00
	lda #$00
	rts
.true:
	ldx #$00
	lda #$01
	rts

__nc_ugt16:
	cpx NC_TMP+1
	bcc .false
	bne .true
	cmp NC_TMP
	bcc .false
	beq .false
.true:
	ldx #$00
	lda #$01
	rts
.false:
	ldx #$00
	lda #$00
	rts

__nc_uge16:
	cpx NC_TMP+1
	bcc .false
	bne .true
	cmp NC_TMP
	bcc .false
.true:
	ldx #$00
	lda #$01
	rts
.false:
	ldx #$00
	lda #$00
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
	ldx #$00
	lda #$00
	rts
.true:
	ldx #$00
	lda #$01
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
	ldx #$00
	lda #$00
	rts
.true:
	ldx #$00
	lda #$01
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
	ldx #$00
	lda #$01
	rts
.false:
	ldx #$00
	lda #$00
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
	ldx #$00
	lda #$01
	rts
.false:
	ldx #$00
	lda #$00
	rts
.sameSign:
	tya
	jmp __nc_uge16
