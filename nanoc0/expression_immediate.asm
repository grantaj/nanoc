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

	;;; try_immediate_binary has already admitted only +, -, exact >> 8,
	;;; comparisons, &, and |. Classify those forms without checking them twice.
	lda reduceOperator
	cmp #OP_SHR
	beq .shift8
	cmp #OP_LT
	bcc .arithmetic		; + or -
	cmp #OP_AND
	bcc .compare		; < <= > >= == !=
.arithmetic:
	jmp emit_arithmetic_immediate
.shift8:
	ldx #<exprImmediateShift8
	ldy #>exprImmediateShift8
	jsr emit_string
	bcs .shiftEmitted
	rts
.shiftEmitted:
	jmp emit_zero_high
.compare:
	jmp emit_compare_immediate

;;; The four arithmetic/bitwise literal forms share one operator prefix. Add
;;; and subtract only add their carry setup before the low byte; the high byte
;;; always begins with the same A/X shuffle.
emit_arithmetic_immediate:
	;;; AND $ffff is already the value in A/X. AND $00ff only clears X.
	lda reduceOperator
	cmp #OP_AND
	bne .ordinary
	lda expressionLiteralValue
	cmp #$ff
	bne .ordinary
	lda expressionLiteralValue+1
	beq .lowMask
	cmp #$ff
	bne .ordinary
	sec
	rts
.lowMask:
	jmp emit_zero_high
.ordinary:
	jsr emit_arithmetic_carry
	bcc .failed
	jsr select_arithmetic_operator
	jsr emit_string
	bcc .failed
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprImmediateHigh
	ldy #>exprImmediateHigh
	jsr emit_string
	bcc .failed
	jsr select_arithmetic_operator
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

;;; Only + and - need explicit carry state before the low byte.
emit_arithmetic_carry:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	bne .none
	ldx #<exprImmediateSec
	ldy #>exprImmediateSec
	jmp emit_string
.add:
	ldx #<exprImmediateClc
	ldy #>exprImmediateClc
	jmp emit_string
.none:
	sec
	rts

;;; The four immediate arithmetic operators are two adjacent pairs in the
;;; operator numbering: +/-, then &/|. Return their shared mnemonic prefix.
select_arithmetic_operator:
	lda reduceOperator
	cmp #OP_AND
	bcc .addSub
	sbc #OP_AND		; carry is set after CMP
	ora #$02
	bne .indexed
.addSub:
	sec
	sbc #OP_ADD
.indexed:
	tax
	ldy arithmeticOperatorHigh,x
	lda arithmeticOperatorLow,x
	tax
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
	bcc .failed
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprImmediateCompareHigh
	ldy #>exprImmediateCompareHigh
	jsr emit_string
	bcc .failed
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprImmediateCompareFinish
	ldy #>exprImmediateCompareFinish
	jsr emit_string
	bcc .failed
	jmp emit_compare_helper_call
.failed:
	clc
	rts

;;; A char is already known to be 0..255. A literal with zero high byte occupies
;;; that same domain after normal integer promotion, so a byte CMP is exact.
emit_byte_compare_immediate:
	lda reduceOperator
	cmp #OP_EQ
	bcs .equality
	cmp #OP_GT
	beq .greater
	cmp #OP_LE
	beq .lessEqual
	jsr emit_cmp_literal_byte
	bcc .failed
	jmp finish_byte_order_compare

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

;;; Finish LT/GE after either immediate or direct-scalar CMP.
finish_byte_order_compare:
	lda reduceOperator
	cmp #OP_GE
	beq .carry
	jmp emit_byte_not_carry_result
.carry:
	jmp emit_byte_carry_result

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
	cmp #OP_LT
	beq .yes
	cmp #OP_GE
	bcc .no
	cmp #OP_AND
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

;;; Both labels name the same byte-comparison emitter. The generic codegen seam
;;; calls the first name; the second states what the routine actually emits.
emit_scalar_binary_reduction:
emit_byte_compare_scalar:
	lda reduceOperator
	cmp #OP_EQ
	bcs .equality
	jsr emit_cmp_primary_scalar
	bcc .failed
	jmp finish_byte_order_compare
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
emit_primary_scalar_line:
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
	ldx primarySymbolIndex
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	jmp emit_persistent_name
.current:
	jmp emit_current_name

emit_immediate_finish:
	ldx #<exprImmediateFinish
	ldy #>exprImmediateFinish
	jmp emit_string

exprImmediateClc:
	byte $09,'c','l','c',$0a,0
exprImmediateSec:
	byte $09,'s','e','c',$0a,0
exprImmediateHigh:
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a,0
exprImmediateAdd:
	byte $09,'a','d','c',' ','#','$',0
exprImmediateSub:
	byte $09,'s','b','c',' ','#','$',0
exprImmediateAnd:
	byte $09,'a','n','d',' ','#','$',0
exprImmediateOr:
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

exprImmediateShift8:
	byte $09,'t','x','a',$0a,0

;;; One pointer pair selects the four shared operator prefixes.
arithmeticOperatorLow:
	byte <exprImmediateAdd,<exprImmediateSub,<exprImmediateAnd,<exprImmediateOr
arithmeticOperatorHigh:
	byte >exprImmediateAdd,>exprImmediateSub,>exprImmediateAnd,>exprImmediateOr
