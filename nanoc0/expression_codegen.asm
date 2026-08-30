;;; expression_codegen.asm
;;;
;;; Direct target-code emission for expression.asm.
;;;
;;; There is deliberately no representation between the expression machine and
;;; these routines. A reduction calls the obvious emitter and ordinary `ass`
;;; source is streamed immediately. Fixed fragments below are the actual 6502
;;; sequences a reader would write by hand.

emit_load_literal:
	lda #exprLdaImmEnd-exprLdaImm
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_text
	bcs .lowPrefix
	rts
.lowPrefix:
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcs .lowValue
	rts
.lowValue:
	jsr emit_newline
	bcs .high
	rts
.high:
	lda #exprLdxImmEnd-exprLdxImm
	ldx #<exprLdxImm
	ldy #>exprLdxImm
	jsr emit_text
	bcs .highPrefix
	rts
.highPrefix:
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcs .done
	rts
.done:
	jmp emit_newline

emit_load_literal_address:
	lda #exprLdaLowImmEnd-exprLdaLowImm
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_text
	bcs .lowName
	rts
.lowName:
	lda currentLiteralIndex
	jsr emit_literal_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	lda #exprLdxHighImmEnd-exprLdxHighImm
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_text
	bcs .highName
	rts
.highName:
	lda currentLiteralIndex
	jsr emit_literal_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_load_primary_scalar:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current

	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcs .persistentLowName
	rts
.persistentLowName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .persistentLowDone
	rts
.persistentLowDone:
	jsr emit_newline
	bcs .persistentWidth
	rts
.persistentWidth:
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	lda #exprLdxSpaceEnd-exprLdxSpace
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_text
	bcs .persistentHighName
	rts
.persistentHighName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .persistentHighDone
	rts
.persistentHighDone:
	jmp emit_plus_one_newline

.current:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcs .currentLowName
	rts
.currentLowName:
	ldx primarySymbolIndex
	jsr emit_current_name
	bcs .currentLowDone
	rts
.currentLowDone:
	jsr emit_newline
	bcs .currentWidth
	rts
.currentWidth:
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	lda #exprLdxSpaceEnd-exprLdxSpace
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_text
	bcs .currentHighName
	rts
.currentHighName:
	ldx primarySymbolIndex
	jsr emit_current_name
	bcs .currentHighDone
	rts
.currentHighDone:
	jmp emit_plus_one_newline

emit_zero_high:
	lda #exprLdxZeroEnd-exprLdxZero
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jmp emit_text

emit_load_primary_address:
	lda #exprLdaLowImmEnd-exprLdaLowImm
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_text
	bcs .lowName
	rts
.lowName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	lda #exprLdxHighImmEnd-exprLdxHighImm
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_text
	bcs .highName
	rts
.highName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_plus_one_newline:
	lda #exprPlusOneEnd-exprPlusOne
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_text
	bcs .done
	rts
.done:
	jmp emit_newline

;;; Spill storage is allocated by expression.asm. This routine merely gives the
;;; new word its deterministic assembler-visible name.
emit_spill_definition:
	sta emitSpillIndex
	jsr emit_spill_name
	bcs .assign
	rts
.assign:
	lda #exprBssAssignEnd-exprBssAssign
	ldx #<exprBssAssign
	ldy #>exprBssAssign
	jsr emit_text
	bcs .offset
	rts
.offset:
	lda allocOffset
	sta emitWord
	lda allocOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcs .done
	rts
.done:
	jmp emit_newline

emit_store_spill:
	sta emitSpillIndex
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcs .lowName
	rts
.lowName:
	lda emitSpillIndex
	jsr emit_spill_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	lda #exprStxSpaceEnd-exprStxSpace
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_text
	bcs .highName
	rts
.highName:
	lda emitSpillIndex
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

;;; X=current-function symbol index; target value already lives in A/X.
emit_store_current_value:
	stx emitSavedIndex
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcs .lowName
	ldx emitSavedIndex
	rts
.lowName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .lowDone
	ldx emitSavedIndex
	rts
.lowDone:
	jsr emit_newline
	bcs .width
	ldx emitSavedIndex
	rts
.width:
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .done
	lda #exprStxSpaceEnd-exprStxSpace
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_text
	bcs .highName
	ldx emitSavedIndex
	rts
.highName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .highDone
	ldx emitSavedIndex
	rts
.highDone:
	jsr emit_plus_one_newline
	bcs .done
	ldx emitSavedIndex
	rts
.done:
	ldx emitSavedIndex
	sec
	rts

emit_unary_minus:
	lda #exprNegateEnd-exprNegate
	ldx #<exprNegate
	ldy #>exprNegate
	jmp emit_text

emit_binary_reduction:
	lda reduceOperator
	cmp #OP_ADD
	beq emit_add_reduction
	cmp #OP_SUB
	beq emit_sub_reduction
	cmp #OP_MUL
	beq emit_mul_reduction
	cmp #OP_AND
	beq emit_and_reduction
	cmp #OP_OR
	beq emit_or_reduction
	cmp #OP_SHL
	beq emit_shl_reduction
	cmp #OP_SHR
	beq emit_shr_reduction
	jmp emit_compare_reduction

;;; A/X is the right operand. Preserve it in the machine-contract scratch pair
;;; while the left spill is loaded.
emit_save_right_tmp:
	lda #exprSaveRightEnd-exprSaveRight
	ldx #<exprSaveRight
	ldy #>exprSaveRight
	jmp emit_text

emit_lda_reduce_spill:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_lda_reduce_spill_high:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

emit_add_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .addLow
	rts
.addLow:
	lda #exprAddLowEnd-exprAddLow
	ldx #<exprAddLow
	ldy #>exprAddLow
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .addHigh
	rts
.addHigh:
	lda #exprAddHighEnd-exprAddHigh
	ldx #<exprAddHigh
	ldy #>exprAddHigh
	jmp emit_text

emit_sub_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .subLow
	rts
.subLow:
	lda #exprSubLowEnd-exprSubLow
	ldx #<exprSubLow
	ldy #>exprSubLow
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .subHigh
	rts
.subHigh:
	lda #exprSubHighEnd-exprSubHigh
	ldx #<exprSubHigh
	ldy #>exprSubHigh
	jmp emit_text

emit_and_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .andLow
	rts
.andLow:
	lda #exprAndLowEnd-exprAndLow
	ldx #<exprAndLow
	ldy #>exprAndLow
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .andHigh
	rts
.andHigh:
	lda #exprAndHighEnd-exprAndHigh
	ldx #<exprAndHigh
	ldy #>exprAndHigh
	jmp emit_text

emit_or_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .orLow
	rts
.orLow:
	lda #exprOrLowEnd-exprOrLow
	ldx #<exprOrLow
	ldy #>exprOrLow
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .orHigh
	rts
.orHigh:
	lda #exprOrHighEnd-exprOrHigh
	ldx #<exprOrHigh
	ldy #>exprOrHigh
	jmp emit_text

;;; __nc_mul16 uses the frozen helper convention: left operand in NC_TMP,
;;; right operand in A/X, result in A/X.
emit_mul_reduction:
	lda #exprMulSaveLowEnd-exprMulSaveLow
	ldx #<exprMulSaveLow
	ldy #>exprMulSaveLow
	jsr emit_text
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	lda #exprStaTmpEnd-exprStaTmp
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .tail
	rts
.tail:
	lda #exprMulTailEnd-exprMulTail
	ldx #<exprMulTail
	ldy #>exprMulTail
	jmp emit_text

emit_shl_reduction:
	lda #$01
	sta shiftLeftFlag
	jmp emit_shift_reduction

emit_shr_reduction:
	lda #$00
	sta shiftLeftFlag

;;; Variable shifts are deliberately a tiny generated loop. Both destinations
;;; are created within this routine, so their relative branches are local by
;;; construction; no distance analysis is required.
emit_shift_reduction:
	jsr reserve_generated_label
	lda emitLabelValue
	sta shiftLoopLabel
	lda emitLabelValue+1
	sta shiftLoopLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta shiftDoneLabel
	lda emitLabelValue+1
	sta shiftDoneLabel+1

	lda #exprShiftCountEnd-exprShiftCount
	ldx #<exprShiftCount
	ldy #>exprShiftCount
	jsr emit_text
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	lda #exprStaTmpEnd-exprStaTmp
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .saveHigh
	rts
.saveHigh:
	lda #exprStaTmpHighEnd-exprStaTmpHigh
	ldx #<exprStaTmpHigh
	ldy #>exprStaTmpHigh
	jsr emit_text
	bcs .zeroCheck
	rts
.zeroCheck:
	lda #exprCpyZeroEnd-exprCpyZero
	ldx #<exprCpyZero
	ldy #>exprCpyZero
	jsr emit_text
	bcs .zeroBranch
	rts
.zeroBranch:
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_text
	bcs .doneName
	rts
.doneName:
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .zeroNewline
	rts
.zeroNewline:
	jsr emit_newline
	bcs .loopLabel
	rts

.loopLabel:
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .bodyChoice
	rts
.bodyChoice:
	lda shiftLeftFlag
	beq .right
	lda #exprShiftLeftBodyEnd-exprShiftLeftBody
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jmp .body
.right:
	lda #exprShiftRightBodyEnd-exprShiftRightBody
	ldx #<exprShiftRightBody
	ldy #>exprShiftRightBody
.body:
	jsr emit_text
	bcs .loopBranch
	rts
.loopBranch:
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_text
	bcs .loopName
	rts
.loopName:
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .loopNewline
	rts
.loopNewline:
	jsr emit_newline
	bcs .doneLabel
	rts
.doneLabel:
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .result
	rts
.result:
	lda #exprLoadTmpResultEnd-exprLoadTmpResult
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jmp emit_text

;;; ---------------------------------------------------------------------------
;;; Comparisons
;;; ---------------------------------------------------------------------------

;;; Every semantic conditional jump uses the same unconditional policy as the
;;; rest of nanoc0: branch only over an adjacent absolute JMP. The compiler does
;;; not ask whether the real target happens to fit in a relative branch.
;;;
;;; Caller places the real target in emitLabelValue and passes the *opposite*
;;; short-branch fragment in A/X/Y. The generated shape is:
;;;
;;;     b<opposite> skip
;;;     jmp target
;;; skip:
;;;
emit_long_conditional_jump:
	sta conditionalBranchLength
	stx conditionalBranchPtr
	sty conditionalBranchPtr+1
	lda emitLabelValue
	sta conditionalTargetLabel
	lda emitLabelValue+1
	sta conditionalTargetLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta conditionalSkipLabel
	lda emitLabelValue+1
	sta conditionalSkipLabel+1

	lda conditionalBranchLength
	ldx conditionalBranchPtr
	ldy conditionalBranchPtr+1
	jsr emit_text
	bcs .skipName
	rts
.skipName:
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .branchDone
	rts
.branchDone:
	jsr emit_newline
	bcs .jump
	rts
.jump:
	lda conditionalTargetLabel
	sta emitLabelValue
	lda conditionalTargetLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcs .skipLabel
	rts
.skipLabel:
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jmp emit_label_definition

set_true_target:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	rts

set_false_target:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	rts

emit_bcc_true:
	jsr set_true_target
	lda #exprBcsEnd-exprBcs
	ldx #<exprBcs
	ldy #>exprBcs
	jmp emit_long_conditional_jump

emit_bcc_false:
	jsr set_false_target
	lda #exprBcsEnd-exprBcs
	ldx #<exprBcs
	ldy #>exprBcs
	jmp emit_long_conditional_jump

emit_bne_true:
	jsr set_true_target
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jmp emit_long_conditional_jump

emit_bne_false:
	jsr set_false_target
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jmp emit_long_conditional_jump

emit_beq_true:
	jsr set_true_target
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump

emit_beq_false:
	jsr set_false_target
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump

emit_bmi_true:
	jsr set_true_target
	lda #exprBplEnd-exprBpl
	ldx #<exprBpl
	ldy #>exprBpl
	jmp emit_long_conditional_jump

emit_bmi_false:
	jsr set_false_target
	lda #exprBplEnd-exprBpl
	ldx #<exprBpl
	ldy #>exprBpl
	jmp emit_long_conditional_jump

emit_bpl_same_sign:
	lda compareSameSignLabel
	sta emitLabelValue
	lda compareSameSignLabel+1
	sta emitLabelValue+1
	lda #exprBmiEnd-exprBmi
	ldx #<exprBmi
	ldy #>exprBmi
	jmp emit_long_conditional_jump

emit_compare_reduction:
	jsr emit_save_right_tmp
	bcs .labels
	rts
.labels:
	jsr reserve_compare_labels
	lda reduceOperator
	cmp #OP_EQ
	beq .equal
	cmp #OP_NE
	beq .notEqual
	jsr combined_integer_type
	cmp #TYPE_UNSIGNED
	beq .unsigned
	jmp emit_signed_relational
.unsigned:
	jmp emit_unsigned_relational
.equal:
	lda #$00
	sta compareInvert
	jmp emit_equality
.notEqual:
	lda #$01
	sta compareInvert
	jmp emit_equality

reserve_compare_labels:
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareTrueLabel
	lda emitLabelValue+1
	sta compareTrueLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareFalseLabel
	lda emitLabelValue+1
	sta compareFalseLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareDoneLabel
	lda emitLabelValue+1
	sta compareDoneLabel+1
	rts

emit_equality:
	jsr emit_lda_reduce_spill
	bcs .lowCompare
	rts
.lowCompare:
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcs .lowBranch
	rts
.lowBranch:
	lda compareInvert
	beq .equalLowDifferent
	jsr emit_bne_true
	jmp .high
.equalLowDifferent:
	jsr emit_bne_false
.high:
	bcs .highLoad
	rts
.highLoad:
	jsr emit_lda_reduce_spill_high
	bcs .highCompare
	rts
.highCompare:
	lda #exprCmpTmpHighEnd-exprCmpTmpHigh
	ldx #<exprCmpTmpHigh
	ldy #>exprCmpTmpHigh
	jsr emit_text
	bcs .highBranch
	rts
.highBranch:
	lda compareInvert
	beq .equalHighSame
	jsr emit_beq_false
	jmp .fallThrough
.equalHighSame:
	jsr emit_beq_true
.fallThrough:
	bcs .fallJump
	rts
.fallJump:
	lda compareInvert
	beq .fallFalse
	jsr set_true_target
	jmp .fallTarget
.fallFalse:
	jsr set_false_target
.fallTarget:
	jsr emit_jump_label
	bcs .results
	rts
.results:
	jmp emit_comparison_result_labels

;;; Unsigned ordering compares high byte first, then low byte when equal.
emit_unsigned_relational:
	jsr emit_lda_reduce_spill_high
	bcs .highCompare
	rts
.highCompare:
	lda #exprCmpTmpHighEnd-exprCmpTmpHigh
	ldx #<exprCmpTmpHigh
	ldy #>exprCmpTmpHigh
	jsr emit_text
	bcs .choose
	rts
.choose:
	lda reduceOperator
	cmp #OP_LT
	beq .lessOrEqual
	cmp #OP_LE
	beq .lessOrEqual
	jmp .greaterOrEqual

.lessOrEqual:
	jsr emit_bcc_true
	bcs .leHighDifferent
	rts
.leHighDifferent:
	jsr emit_bne_false
	bcs .leLow
	rts
.leLow:
	jsr emit_lda_reduce_spill
	bcs .leLowCompare
	rts
.leLowCompare:
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcs .leLowBranch
	rts
.leLowBranch:
	lda reduceOperator
	cmp #OP_LT
	beq .strictLess
	jsr emit_bcc_true
	bcs .leEqual
	rts
.leEqual:
	jsr emit_beq_true
	bcs .fallFalse
	rts
.strictLess:
	jsr emit_bcc_true
	bcs .fallFalse
	rts

.greaterOrEqual:
	jsr emit_bcc_false
	bcs .geHighDifferent
	rts
.geHighDifferent:
	jsr emit_bne_true
	bcs .geLow
	rts
.geLow:
	jsr emit_lda_reduce_spill
	bcs .geLowCompare
	rts
.geLowCompare:
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcs .geLowBranch
	rts
.geLowBranch:
	lda reduceOperator
	cmp #OP_GT
	beq .strictGreater
	jsr emit_bcc_false
	bcs .fallTrue
	rts
.strictGreater:
	jsr emit_bcc_false
	bcs .gtEqual
	rts
.gtEqual:
	jsr emit_beq_false
	bcs .fallTrue
	rts

.fallTrue:
	jsr set_true_target
	jmp .fallJump
.fallFalse:
	jsr set_false_target
.fallJump:
	jsr emit_jump_label
	bcs .results
	rts
.results:
	jmp emit_comparison_result_labels

;;; For signed ordering, differing sign bits decide immediately. If signs match,
;;; ordinary unsigned byte ordering is correct for two's-complement values.
emit_signed_relational:
	jsr emit_lda_reduce_spill_high
	bcs .signCompare
	rts
.signCompare:
	lda #exprEorTmpHighEnd-exprEorTmpHigh
	ldx #<exprEorTmpHigh
	ldy #>exprEorTmpHigh
	jsr emit_text
	bcs .sameSignLabel
	rts
.sameSignLabel:
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareSameSignLabel
	lda emitLabelValue+1
	sta compareSameSignLabel+1
	jsr emit_bpl_same_sign
	bcs .differentSigns
	rts
.differentSigns:
	jsr emit_lda_reduce_spill_high
	bcs .signBranch
	rts
.signBranch:
	lda reduceOperator
	cmp #OP_LT
	beq .negativeMeansTrue
	cmp #OP_LE
	beq .negativeMeansTrue
	jsr emit_bmi_false
	bcs .positiveTrue
	rts
.negativeMeansTrue:
	jsr emit_bmi_true
	bcs .positiveFalse
	rts
.positiveTrue:
	jsr set_true_target
	jmp .differentJump
.positiveFalse:
	jsr set_false_target
.differentJump:
	jsr emit_jump_label
	bcs .sameSign
	rts
.sameSign:
	lda compareSameSignLabel
	sta emitLabelValue
	lda compareSameSignLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .sameSignCompare
	rts
.sameSignCompare:
	jmp emit_unsigned_relational

emit_jump_label:
	lda #exprJmpEnd-exprJmp
	ldx #<exprJmp
	ldy #>exprJmp
	jsr emit_text
	bcs .name
	rts
.name:
	jsr emit_generated_label_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_label_definition:
	jsr emit_generated_label_name
	bcs .colon
	rts
.colon:
	lda #':'
	jsr emit_output_byte
	bcs .done
	rts
.done:
	jmp emit_newline

emit_comparison_result_labels:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .trueValue
	rts
.trueValue:
	lda #exprTrueValueEnd-exprTrueValue
	ldx #<exprTrueValue
	ldy #>exprTrueValue
	jsr emit_text
	bcs .skipFalse
	rts
.skipFalse:
	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcs .falseLabel
	rts
.falseLabel:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .falseValue
	rts
.falseValue:
	lda #exprFalseValueEnd-exprFalseValue
	ldx #<exprFalseValue
	ldy #>exprFalseValue
	jsr emit_text
	bcs .doneLabel
	rts
.doneLabel:
	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jmp emit_label_definition

;;; Index value is in target A/X. reduceSpill is the saved full 16-bit base.
;;; Non-char global arrays scale the index by two before address addition.
emit_index_load:
	jsr emit_save_right_tmp
	bcs .scale
	rts
.scale:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .leftLow
	lda #exprScaleIndexEnd-exprScaleIndex
	ldx #<exprScaleIndex
	ldy #>exprScaleIndex
	jsr emit_text
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .addressLow
	rts
.addressLow:
	lda #exprIndexLowEnd-exprIndexLow
	ldx #<exprIndexLow
	ldy #>exprIndexLow
	jsr emit_text
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .addressHigh
	rts
.addressHigh:
	lda #exprIndexHighEnd-exprIndexHigh
	ldx #<exprIndexHigh
	ldy #>exprIndexHigh
	jsr emit_text
	bcs .load
	rts
.load:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .char
	lda #exprWordIndirectEnd-exprWordIndirect
	ldx #<exprWordIndirect
	ldy #>exprWordIndirect
	jmp emit_text
.char:
	lda #exprCharIndirectEnd-exprCharIndirect
	ldx #<exprCharIndirect
	ldy #>exprCharIndirect
	jmp emit_text

;;; ---------------------------------------------------------------------------
;;; Fixed target-source fragments
;;; ---------------------------------------------------------------------------

exprLdaImm:		byte $09,'l','d','a',' ','#','$'
exprLdaImmEnd:
exprLdxImm:		byte $09,'l','d','x',' ','#','$'
exprLdxImmEnd:
exprLdaLowImm:		byte $09,'l','d','a',' ','#','<'
exprLdaLowImmEnd:
exprLdxHighImm:		byte $09,'l','d','x',' ','#','>'
exprLdxHighImmEnd:
exprLdaSpace:		byte $09,'l','d','a',' '
exprLdaSpaceEnd:
exprLdxSpace:		byte $09,'l','d','x',' '
exprLdxSpaceEnd:
exprStaSpace:		byte $09,'s','t','a',' '
exprStaSpaceEnd:
exprStxSpace:		byte $09,'s','t','x',' '
exprStxSpaceEnd:
exprLdxZero:		byte $09,'l','d','x',' ','#','$','0','0',$0a
exprLdxZeroEnd:
exprPlusOne:		byte '+','1'
exprPlusOneEnd:
exprBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
exprBssAssignEnd:
exprBytePrefix:		byte $09,'b','y','t','e',' '
exprBytePrefixEnd:

exprNegate:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprNegateEnd:

exprSaveRight:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
exprSaveRightEnd:
exprAddLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAddLowEnd:
exprAddHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAddHighEnd:
exprSubLow:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprSubLowEnd:
exprSubHigh:
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprSubHighEnd:
exprAndLow:
	byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAndLowEnd:
exprAndHigh:
	byte $09,'a','n','d',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAndHighEnd:
exprOrLow:
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprOrLowEnd:
exprOrHigh:
	byte $09,'o','r','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprOrHighEnd:

exprMulSaveLow:		byte $09,'t','a','y',$0a
exprMulSaveLowEnd:
exprStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
exprStaTmpEnd:
exprStaTmpHigh:		byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
exprStaTmpHighEnd:
exprMulTail:
	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','y','a',$0a
	byte $09,'j','s','r',' ','_','_','n','c','_','m','u','l','1','6',$0a
exprMulTailEnd:

exprShiftCount:		byte $09,'t','a','y',$0a
exprShiftCountEnd:
exprCpyZero:		byte $09,'c','p','y',' ','#','$','0','0',$0a
exprCpyZeroEnd:
exprShiftLeftBody:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'d','e','y',$0a
exprShiftLeftBodyEnd:
exprShiftRightBody:
	byte $09,'l','s','r',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','T','M','P',$0a
	byte $09,'d','e','y',$0a
exprShiftRightBodyEnd:
exprLoadTmpResult:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','x',' ','N','C','_','T','M','P','+','1',$0a
exprLoadTmpResultEnd:

exprCmpTmp:		byte $09,'c','m','p',' ','N','C','_','T','M','P',$0a
exprCmpTmpEnd:
exprCmpTmpHigh:		byte $09,'c','m','p',' ','N','C','_','T','M','P','+','1',$0a
exprCmpTmpHighEnd:
exprEorTmpHigh:		byte $09,'e','o','r',' ','N','C','_','T','M','P','+','1',$0a
exprEorTmpHighEnd:
exprBcc:		byte $09,'b','c','c',' '
exprBccEnd:
exprBcs:		byte $09,'b','c','s',' '
exprBcsEnd:
exprBne:		byte $09,'b','n','e',' '
exprBneEnd:
exprBeq:		byte $09,'b','e','q',' '
exprBeqEnd:
exprBmi:		byte $09,'b','m','i',' '
exprBmiEnd:
exprBpl:		byte $09,'b','p','l',' '
exprBplEnd:
exprJmp:		byte $09,'j','m','p',' '
exprJmpEnd:
exprTrueValue:
	byte $09,'l','d','a',' ','#','$','0','1',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprTrueValueEnd:
exprFalseValue:
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprFalseValueEnd:

exprScaleIndex:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
exprScaleIndexEnd:
exprIndexLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
exprIndexLowEnd:
exprIndexHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R','+','1',$0a
exprIndexHighEnd:
exprCharIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprCharIndirectEnd:
exprWordIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'t','a','x',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
exprWordIndirectEnd:

;;; Scratch used only while formatting generated control flow.
conditionalBranchLength:	byte 0
conditionalBranchPtr:		word 0
conditionalTargetLabel:	word 0
conditionalSkipLabel:		word 0
