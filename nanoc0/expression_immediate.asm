;;; expression_immediate.asm
;;;
;;; Direct target emission for the small literal-RHS fast path in expression.asm.
;;;
;;; The ordinary expression machine leaves the left operand in A/X when it sees
;;; a binary operator. If the right operand is one literal and no tighter
;;; operator follows it, there is no value to preserve across later generated
;;; code: apply the literal to A/X directly instead of allocating a spill word.
;;;
;;; Arithmetic/bitwise literals use direct immediate instructions. A char on the
;;; left and a literal in the byte range also compare directly as bytes. Wider
;;; comparisons retain the shared 16-bit helper path.

emit_immediate_binary_reduction:
	lda #$00
	sta expressionTruthInZ
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
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
.add:
	jmp emit_add_immediate
.sub:
	jmp emit_sub_immediate
.and:
	jmp emit_and_immediate
.or:
	jmp emit_or_immediate
.compare:
	jmp emit_compare_immediate

emit_add_immediate:
	ldx #<exprImmediateAddLow
	ldy #>exprImmediateAddLow
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
	ldx #<exprImmediateAddHigh
	ldy #>exprImmediateAddHigh
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
	jmp emit_immediate_finish

emit_sub_immediate:
	ldx #<exprImmediateSubLow
	ldy #>exprImmediateSubLow
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
	ldx #<exprImmediateSubHigh
	ldy #>exprImmediateSubHigh
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
	jmp emit_immediate_finish

emit_and_immediate:
	ldx #<exprImmediateAndLow
	ldy #>exprImmediateAndLow
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
	ldx #<exprImmediateAndHigh
	ldy #>exprImmediateAndHigh
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
	jmp emit_immediate_finish

emit_or_immediate:
	ldx #<exprImmediateOrLow
	ldy #>exprImmediateOrLow
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
	ldx #<exprImmediateOrHigh
	ldy #>exprImmediateOrHigh
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
	jmp emit_immediate_finish

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
;;; that same domain after the normal integer promotions, so a byte CMP is exact.
;;; For > and <=, comparing against literal+1 turns the test into >= or <. The
;;; $ff edge is the corresponding constant false/true result; the literal scratch
;;; is dead after this reduction, so incrementing it needs no retained state.
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
