;;; expression_immediate.asm
;;;
;;; Direct target emission for simple right-hand operands.
;;;
;;; A simple literal or scalar can often be consumed before the ordinary spill
;;; machine is needed. The physical-value helpers in expression_codegen.asm make
;;; that decision independent of the source C type: a byte stays in A until a
;;; real word consumer asks for X, and a comparison stays in flags until a value
;;; consumer asks for 0/1.

emit_immediate_binary_reduction:
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
	jsr ensure_expression_word
	bcc .failed
	ldx #<exprImmediateShift8
	ldy #>exprImmediateShift8
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z
.compare:
	jmp emit_compare_immediate
.failed:
	clc
	rts

;;; The four arithmetic/bitwise literal forms share one operator prefix. When the
;;; whole scalar assignment stores a char, only the low result is observable and
;;; +, -, &, | can stay byte-native. Every other consumer keeps the full promoted
;;; integer result.
emit_arithmetic_immediate:
	;;; AND $ffff is an identity. It may still have to materialise a preceding
	;;; comparison, but it never needs to manufacture a high byte just for tidiness.
	lda reduceOperator
	cmp #OP_AND
	bne .widthChoice
	lda expressionLiteralValue
	cmp #$ff
	bne .widthChoice
	lda expressionLiteralValue+1
	beq .lowMask
	cmp #$ff
	bne .widthChoice
	jmp materialize_expression_value

.lowMask:
	;;; The low byte is already the correct result. If the input was a word, its
	;;; final LDX did not leave Z describing A, so narrowing deliberately forgets
	;;; any live truth flag.
	jsr ensure_expression_byte_value
	bcc .failed
	jmp narrow_expression_to_byte

.widthChoice:
	jsr byte_result_is_final_scalar_assignment
	bcc .word
	jsr ensure_expression_byte_value
	bcc .failed
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
	jmp mark_expression_byte_z

.word:
	jsr ensure_expression_word
	bcc .failed
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
	jsr ensure_expression_word
	bcc .failed
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
;;; that same domain after normal integer promotion, so one CMP is exact. Keep the
;;; result in the processor flags; a later value consumer materialises 0/1 only if
;;; it really needs it.
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
	lda #EXPR_CONDITION_BCS
	jmp mark_expression_condition
.lessEqual:
	lda expressionLiteralValue
	cmp #$ff
	beq .true
	inc expressionLiteralValue
	jsr emit_cmp_literal_byte
	bcc .failed
	lda #EXPR_CONDITION_BCC
	jmp mark_expression_condition

.equality:
	jsr emit_cmp_literal_byte
	bcc .failed
	lda reduceOperator
	cmp #OP_EQ
	bne .notEqual
	lda #EXPR_CONDITION_BEQ
	jmp mark_expression_condition
.notEqual:
	lda #EXPR_CONDITION_BNE
	jmp mark_expression_condition
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
	lda #EXPR_CONDITION_BCC
	jmp mark_expression_condition
.carry:
	lda #EXPR_CONDITION_BCS
	jmp mark_expression_condition

;;; ---------------------------------------------------------------------------
;;; Direct scalar forms
;;; ---------------------------------------------------------------------------

;;; A simple scalar RHS can be addressed by the target instruction itself. Keep
;;; char comparisons direct as before, and add the low-byte arithmetic case when
;;; the complete enclosing scalar assignment stores a char.
scalar_operator_is_direct:
	jsr byte_result_is_final_scalar_assignment
	bcc .compare
	lda reduceOperator
	cmp #OP_ADD
	beq .yes
	cmp #OP_SUB
	beq .yes
	cmp #OP_AND
	beq .yes
	cmp #OP_OR
	beq .yes
.compare:
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

emit_scalar_binary_reduction:
	jsr byte_result_is_final_scalar_assignment
	bcc .compare
	lda reduceOperator
	cmp #OP_ADD
	beq emit_byte_scalar_arithmetic
	cmp #OP_SUB
	beq emit_byte_scalar_arithmetic
	cmp #OP_AND
	beq emit_byte_scalar_arithmetic
	cmp #OP_OR
	beq emit_byte_scalar_arithmetic
.compare:
	jmp emit_byte_compare_scalar

emit_byte_scalar_arithmetic:
	jsr ensure_expression_byte_value
	bcc .failed
	jsr emit_arithmetic_carry
	bcc .failed
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_AND
	beq .and
	ldx #<exprOraSpace
	ldy #>exprOraSpace
	jmp .emit
.add:
	ldx #<exprAdcSpace
	ldy #>exprAdcSpace
	jmp .emit
.sub:
	ldx #<exprSbcSpace
	ldy #>exprSbcSpace
	jmp .emit
.and:
	ldx #<exprAndSpace
	ldy #>exprAndSpace
.emit:
	jsr emit_primary_scalar_line
	bcc .failed
	jmp mark_expression_byte_z
.failed:
	clc
	rts

;;; Both labels name the same byte-comparison emitter. The generic codegen seam
;;; calls the first name; the second states what the routine actually emits.
emit_byte_compare_scalar:
	jsr emit_cmp_primary_scalar
	bcc .failed
	lda reduceOperator
	cmp #OP_EQ
	beq .equal
	cmp #OP_NE
	beq .notEqual
	jmp finish_byte_order_compare
.equal:
	lda #EXPR_CONDITION_BEQ
	jmp mark_expression_condition
.notEqual:
	lda #EXPR_CONDITION_BNE
	jmp mark_expression_condition
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

;;; At this exact reduction point currentToken is already the token after the
;;; simple RHS. A semicolon plus the still-live scalar-assignment marker proves
;;; that this operator's low byte is the final observable result.
byte_result_is_final_scalar_assignment:
	lda statementTargetKind
	cmp #STATEMENT_SCALAR_ASSIGNMENT
	bne .no
	lda statementTargetType
	cmp #TYPE_CHAR
	bne .no
	lda currentTokenKind
	cmp #';'
	bne .no
	sec
	rts
.no:
	clc
	rts

emit_immediate_finish:
	ldx #<exprImmediateFinish
	ldy #>exprImmediateFinish
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

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

exprAdcSpace:	byte $09,'a','d','c',' ',0
exprSbcSpace:	byte $09,'s','b','c',' ',0
exprAndSpace:	byte $09,'a','n','d',' ',0
exprOraSpace:	byte $09,'o','r','a',' ',0

;;; One pointer pair selects the four shared operator prefixes.
arithmeticOperatorLow:
	byte <exprImmediateAdd,<exprImmediateSub,<exprImmediateAnd,<exprImmediateOr
arithmeticOperatorHigh:
	byte >exprImmediateAdd,>exprImmediateSub,>exprImmediateAnd,>exprImmediateOr
