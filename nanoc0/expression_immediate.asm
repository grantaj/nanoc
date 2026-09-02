;;; expression_immediate.asm
;;;
;;; Direct target emission for simple right-hand operands.
;;;
;;; The ordinary expression machine leaves the left operand in A/X when it sees
;;; a binary operator. A literal can be applied directly. A plain scalar may also
;;; avoid a static spill; byte comparisons are cheap enough to address the scalar
;;; itself, while wider/arithmetic cases use the existing bounded NC_PTR transient
;;; convention. There is no retained expression representation or optimizer.

emit_immediate_binary_reduction:
	lda #$00
	sta expressionTruthInZ
	lda reduceOperator
	cmp #OP_ADD
	beq .arithmetic
	cmp #OP_SUB
	beq .arithmetic
	cmp #OP_AND
	beq .arithmetic
	cmp #OP_OR
	beq .arithmetic
	cmp #OP_LT
	beq .compare
	cmp #OP_LE
	beq .compare
	cmp #OP_GT
	beq .compare
	cmp #OP_GE
	beq .compare
	cmp #OP_EQ
	beq .compare
	cmp #OP_NE
	beq .compare
	clc
	rts
.arithmetic:
	jmp emit_arithmetic_immediate
.compare:
	jmp emit_compare_immediate

;;; The four arithmetic/bitwise literal forms differ only in instruction name.
emit_arithmetic_immediate:
	jsr select_arithmetic_low
	bcc .failed
	jsr emit_string
	bcc .failed
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	jsr select_arithmetic_high
	bcc .failed
	jsr emit_string
	bcc .failed
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	jmp emit_immediate_finish
.failed:
	clc
	rts

select_arithmetic_low:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
	clc
	rts
.add:
	ldx #<exprImmediateAddLow
	ldy #>exprImmediateAddLow
	sec
	rts
.sub:
	ldx #<exprImmediateSubLow
	ldy #>exprImmediateSubLow
	sec
	rts
.and:
	ldx #<exprImmediateAndLow
	ldy #>exprImmediateAndLow
	sec
	rts
.or:
	ldx #<exprImmediateOrLow
	ldy #>exprImmediateOrLow
	sec
	rts

select_arithmetic_high:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
	clc
	rts
.add:
	ldx #<exprImmediateAddHigh
	ldy #>exprImmediateAddHigh
	sec
	rts
.sub:
	ldx #<exprImmediateSubHigh
	ldy #>exprImmediateSubHigh
	sec
	rts
.and:
	ldx #<exprImmediateAndHigh
	ldy #>exprImmediateAndHigh
	sec
	rts
.or:
	ldx #<exprImmediateOrHigh
	ldy #>exprImmediateOrHigh
	sec
	rts

emit_compare_immediate:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .word
	lda expressionLiteralValue+1
	bne .word
	jmp emit_byte_compare_immediate
.word:
	ldx #<exprImmediateCompareLow
	ldy #>exprImmediateCompareLow
	jsr emit_string
	bcs .low
	rts
.low:
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .highPrefix
	rts
.highPrefix:
	ldx #<exprImmediateCompareHigh
	ldy #>exprImmediateCompareHigh
	jsr emit_string
	bcs .high
	rts
.high:
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcs .highDone
	rts
.highDone:
	jsr emit_newline
	bcs .finish
	rts
.finish:
	ldx #<exprImmediateCompareFinish
	ldy #>exprImmediateCompareFinish
	jsr emit_string
	bcs .call
	rts
.call:
	jmp emit_compare_helper_call

;;; A char is already known to be 0..255. A literal with zero high byte occupies
;;; that same domain after normal integer promotion, so a byte CMP is exact.
emit_byte_compare_immediate:
	lda reduceOperator
	cmp #OP_EQ
	beq .equality
	cmp #OP_NE
	beq .equality
	cmp #OP_GT
	beq .greater
	cmp #OP_LE
	beq .lessEqual
	jsr emit_cmp_literal_byte
	bcc .failed
	lda reduceOperator
	cmp #OP_GE
	beq .carry
	jmp emit_byte_not_carry_result
.carry:
	jmp emit_byte_carry_result

.greater:
	lda expressionLiteralValue
	cmp #$ff
	beq .false
	inc expressionLiteralValue
	jsr emit_cmp_literal_byte
	bcc .failed
	jmp emit_byte_carry_result
.lessEqual:
	lda expressionLiteralValue
	cmp #$ff
	beq .true
	inc expressionLiteralValue
	jsr emit_cmp_literal_byte
	bcc .failed
	jmp emit_byte_not_carry_result

.equality:
	jsr begin_byte_equality
	bcc .failed
	jsr emit_cmp_literal_byte
	bcc .failed
	jmp finish_byte_equality
.false:
	jmp emit_byte_false_result
.true:
	jmp emit_byte_true_result
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Direct scalar byte comparisons
;;; ---------------------------------------------------------------------------

;;; Only the dominant char comparison case bypasses the NC_PTR transient. EQ/NE
;;; and LT/GE map directly to CMP flags. GT/LE need carry plus equality and stay
;;; on the existing reversed transient path; wider comparisons keep their shared
;;; 16-bit helper path. This keeps the compiler smaller than the code it saves.
scalar_operator_is_direct:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .no
	lda reduceRightType
	cmp #TYPE_CHAR
	bne .no
	lda reduceOperator
	cmp #OP_EQ
	beq .yes
	cmp #OP_NE
	beq .yes
	cmp #OP_LT
	beq .yes
	cmp #OP_GE
	beq .yes
.no:
	clc
	rts
.yes:
	sec
	rts

emit_scalar_binary_reduction:
	lda #$00
	sta expressionTruthInZ
	jmp emit_byte_compare_scalar

emit_byte_compare_scalar:
	lda reduceOperator
	cmp #OP_EQ
	beq .equality
	cmp #OP_NE
	beq .equality
	jsr emit_cmp_primary_scalar
	bcc .failed
	lda reduceOperator
	cmp #OP_GE
	beq .carry
	jmp emit_byte_not_carry_result
.carry:
	jmp emit_byte_carry_result
.equality:
	jsr begin_byte_equality
	bcc .failed
	jsr emit_cmp_primary_scalar
	bcc .failed
	jmp finish_byte_equality
.failed:
	clc
	rts

emit_cmp_primary_scalar:
	ldx #<exprCmpSpace
	ldy #>exprCmpSpace
	jsr emit_string
	bcc .failed
	jsr emit_primary_scalar_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; Format the captured scalar without emitting a load instruction.
emit_primary_scalar_name:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	ldx primarySymbolIndex
	jmp emit_persistent_name
.current:
	ldx primarySymbolIndex
	jmp emit_current_name

emit_immediate_finish:
	ldx #<exprImmediateFinish
	ldy #>exprImmediateFinish
	jmp emit_string

exprImmediateAddLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','#','$',0
exprImmediateAddHigh:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'a','d','c',' ','#','$',0
exprImmediateSubLow:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','#','$',0
exprImmediateSubHigh:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'s','b','c',' ','#','$',0
exprImmediateAndLow:
	byte $09,'a','n','d',' ','#','$',0
exprImmediateAndHigh:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'a','n','d',' ','#','$',0
exprImmediateOrLow:
	byte $09,'o','r','a',' ','#','$',0
exprImmediateOrHigh:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'o','r','a',' ','#','$',0
exprImmediateCompareLow:
	byte $09,'t','a','y',$0a
	byte $09,'l','d','a',' ','#','$',0
exprImmediateCompareHigh:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','a',' ','#','$',0
exprImmediateCompareFinish:
	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','y','a',$0a,0
exprImmediateFinish:
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a,0
