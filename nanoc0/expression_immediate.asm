;;; expression_immediate.asm
;;;
;;; Direct target emission for simple right-hand operands.
;;;
;;; The ordinary expression machine leaves the left operand in A/X when it sees
;;; a binary operator. If the right operand is one literal or ordinary scalar and
;;; no tighter operator follows it, there is no later evaluation that can clobber
;;; the left value. Apply that RHS directly instead of allocating a spill word.
;;;
;;; Literals use immediate instructions. Scalars use their assembler-visible
;;; memory operand directly for arithmetic and byte comparisons; wider scalar
;;; comparisons load only the RHS into NC_TMP for the shared comparison helpers.
;;; There is still no retained expression representation or optimizer.

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

;;; The four arithmetic/bitwise literal forms differ only in the instruction
;;; spelling. Keep one emission path and select the tiny fixed prefix explicitly.
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

;;; Carry set: X/Y names the low immediate fragment and A is the length through
;;; the trailing operand space, excluding '#$'. Scalar emission uses that prefix
;;; length; literal emission simply streams the whole NUL-terminated fragment.
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
	lda #10
	ldx #<exprImmediateAddLow
	ldy #>exprImmediateAddLow
	sec
	rts
.sub:
	lda #10
	ldx #<exprImmediateSubLow
	ldy #>exprImmediateSubLow
	sec
	rts
.and:
	lda #5
	ldx #<exprImmediateAndLow
	ldy #>exprImmediateAndLow
	sec
	rts
.or:
	lda #5
	ldx #<exprImmediateOrLow
	ldy #>exprImmediateOrLow
	sec
	rts

;;; Carry set: X/Y names the high fragment. Every direct scalar prefix ends just
;;; before '#$' at byte 15: TAY, TXA, then the high-byte operation and a space.
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

;;; ---------------------------------------------------------------------------
;;; Direct scalar RHS
;;; ---------------------------------------------------------------------------

;;; GT and LE retain the existing NC_PTR transient path. Their byte form needs
;;; both carry and equality, so keeping that already-correct path is clearer than
;;; adding a second local-branch materialiser for rare cases. Every other scalar
;;; operator admitted by try_immediate_binary can address the RHS directly.
scalar_operator_is_direct:
	lda reduceOperator
	cmp #OP_GT
	beq .no
	cmp #OP_LE
	beq .no
	sec
	rts
.no:
	clc
	rts

emit_scalar_binary_reduction:
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
	cmp #OP_GE
	beq .compare
	cmp #OP_EQ
	beq .compare
	cmp #OP_NE
	beq .compare
	clc
	rts
.arithmetic:
	jmp emit_arithmetic_scalar
.compare:
	jmp emit_compare_scalar

;;; A/X is still the left operand. Stream OP rhs directly, then perform the high
;;; byte through TXA. A char RHS has a statically zero high byte, so use the same
;;; immediate fragment with #$00 rather than manufacturing a load.
emit_arithmetic_scalar:
	jsr select_arithmetic_low
	bcc .failed
	jsr emit_text
	bcc .failed
	jsr emit_primary_scalar_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	jsr select_arithmetic_high
	bcc .failed
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq .charHigh
	lda #15
	jsr emit_text
	bcc .failed
	jsr emit_primary_scalar_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
	jmp emit_immediate_finish
.charHigh:
	jsr emit_string
	bcc .failed
	lda #$00
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	jmp emit_immediate_finish
.failed:
	clc
	rts

;;; Format the scalar captured by expression.asm without emitting an instruction.
;;; Current symbols are function parameters/locals; persistent symbols are globals.
emit_primary_scalar_name:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	ldx primarySymbolIndex
	jmp emit_persistent_name
.current:
	ldx primarySymbolIndex
	jmp emit_current_name

emit_compare_scalar:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .word
	lda reduceRightType
	cmp #TYPE_CHAR
	bne .word
	jmp emit_byte_compare_scalar

.word:
	;;; Preserve only the left low byte in Y while the RHS is loaded into NC_TMP.
	;;; LDA does not disturb X, so the left high byte remains live throughout.
	ldx #<exprMulSaveLow
	ldy #>exprMulSaveLow
	jsr emit_string
	bcc .failed
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcc .failed
	jsr emit_primary_scalar_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_string
	bcc .failed
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq .zeroHigh
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcc .failed
	jsr emit_primary_scalar_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
	jmp .saveHigh
.zeroHigh:
	ldx #<exprByteFalse
	ldy #>exprByteFalse
	jsr emit_string
	bcc .failed
.saveHigh:
	ldx #<exprStaTmpHigh
	ldy #>exprStaTmpHigh
	jsr emit_string
	bcc .failed
	ldx #<exprTya
	ldy #>exprTya
	jsr emit_string
	bcc .failed
	jmp emit_compare_helper_call
.failed:
	clc
	rts

;;; Direct char/scalar comparisons need only CMP rhs. GT and LE deliberately do
;;; not arrive here; scalar_operator_is_direct leaves them on the existing
;;; reversed transient path where equality is already handled explicitly.
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
