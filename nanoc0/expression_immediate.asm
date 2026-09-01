;;; expression_immediate.asm
;;;
;;; Direct target emission for the small literal-RHS fast path in expression.asm.
;;;
;;; The ordinary expression machine leaves the left operand in A/X when it sees
;;; a binary operator. If the right operand is one literal and no tighter
;;; operator follows it, there is no value to preserve across later generated
;;; code: apply the literal to A/X directly instead of allocating a spill word.
;;;
;;; Arithmetic/bitwise literals use direct immediate instructions. Comparisons
;;; keep the same shared 16-bit helpers as ordinary reductions, but place the
;;; literal straight in NC_TMP while preserving the left value in A/X.

emit_immediate_binary_reduction:
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
