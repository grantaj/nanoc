;;; ---------------------------------------------------------------------------
;;; Comparisons
;;; ---------------------------------------------------------------------------

;;; Statement destinations may be arbitrarily far away. For those real semantic
;;; jumps, branch over one adjacent absolute JMP so the relative branch remains
;;; local without any distance analysis.
emit_long_conditional_jump:
	jsr begin_conditional_jump
	jsr emit_branch_to_conditional_skip
	bcc .failed
	jmp finish_conditional_jump
.failed:
	jsr restore_conditional_target
	clc
	rts

begin_conditional_jump:
	lda emitLabelValue
	sta conditionalTargetLabel
	lda emitLabelValue+1
	sta conditionalTargetLabel+1
	lda emitLabelKind
	sta conditionalTargetKind
	jsr reserve_generated_label
	lda emitLabelValue
	sta conditionalSkipLabel
	lda emitLabelValue+1
	sta conditionalSkipLabel+1
	rts

emit_branch_to_conditional_skip:
	jsr emit_string
	bcc .failed
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

finish_conditional_jump:
	jsr restore_conditional_target
	jsr emit_jump_label
	bcc .failed
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	php
	jsr restore_conditional_target
	plp
	rts
.failed:
	jsr restore_conditional_target
	clc
	rts

restore_conditional_target:
	lda conditionalTargetLabel
	sta emitLabelValue
	lda conditionalTargetLabel+1
	sta emitLabelValue+1
	lda conditionalTargetKind
	sta emitLabelKind
	rts

;;; Both char operands already occupy the exact 0..255 domain after promotion,
;;; so their high bytes cannot affect a comparison. Use the ordinary 6502 byte
;;; forms and leave X at zero. Wider operands retain the explicit 16-bit helper
;;; path below.
emit_compare_reduction:
	jsr left_operand_is_byte_domain
	bcc .word
	jsr right_operand_is_byte_domain
	bcc .word
	jmp emit_byte_compare_reduction
.word:
	;;; The shared 16-bit helpers expect left in A/X and right in NC_TMP.
	jsr materialize_expression_word
	bcs .saveRight
	rts
.saveRight:
	jsr emit_save_right_tmp
	bcs .left
	rts
.left:
	jsr materialize_saved_word
	bcs .call
	rts
.call:
	jmp emit_compare_helper_call

emit_byte_compare_reduction:
	jsr right_operand_is_direct
	bcc .savedRight
	jsr materialize_saved_byte
	bcs .directCmp
	rts
.directCmp:
	ldx #<exprCmpSpace
	ldy #>exprCmpSpace
	jsr emit_right_low_operand
	bcs .mark
	rts
.savedRight:
	jsr materialize_expression_byte
	bcs .save
	rts
.save:
	jsr emit_save_right_byte_tmp
	bcs .left
	rts
.left:
	jsr materialize_saved_byte
	bcs .tmpCmp
	rts
.tmpCmp:
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_string
	bcs .mark
	rts
.mark:
	lda reduceOperator
	cmp #OP_EQ
	beq .eq
	cmp #OP_NE
	beq .ne
	cmp #OP_LT
	beq .lt
	cmp #OP_GE
	beq .ge
	cmp #OP_GT
	beq .gt
	lda #VALUE_COND_LE
	jmp mark_expression_condition
.eq:
	lda #VALUE_COND_EQ
	jmp mark_expression_condition
.ne:
	lda #VALUE_COND_NE
	jmp mark_expression_condition
.lt:
	lda #VALUE_COND_LT
	jmp mark_expression_condition
.ge:
	lda #VALUE_COND_GE
	jmp mark_expression_condition
.gt:
	lda #VALUE_COND_GT
	jmp mark_expression_condition

;;; A/X is the left operand and NC_TMP the right. Select the one shared helper
;;; from the source operator and the usual Phase 1 integer-conversion rule.
emit_compare_helper_call:
	lda #$01
	sta compareUsed
	lda reduceOperator
	cmp #OP_EQ
	beq .equal
	cmp #OP_NE
	beq .notEqual
	jsr combined_integer_type
	cmp #TYPE_UNSIGNED
	beq .unsigned

	lda reduceOperator
	cmp #OP_LT
	beq .signedLt
	cmp #OP_LE
	beq .signedLe
	cmp #OP_GT
	beq .signedGt
	ldx #<exprCallSge16
	ldy #>exprCallSge16
	jmp emit_compare_call
.signedLt:
	ldx #<exprCallSlt16
	ldy #>exprCallSlt16
	jmp emit_compare_call
.signedLe:
	ldx #<exprCallSle16
	ldy #>exprCallSle16
	jmp emit_compare_call
.signedGt:
	ldx #<exprCallSgt16
	ldy #>exprCallSgt16
	jmp emit_compare_call

.unsigned:
	lda reduceOperator
	cmp #OP_LT
	beq .unsignedLt
	cmp #OP_LE
	beq .unsignedLe
	cmp #OP_GT
	beq .unsignedGt
	ldx #<exprCallUge16
	ldy #>exprCallUge16
	jmp emit_compare_call
.unsignedLt:
	ldx #<exprCallUlt16
	ldy #>exprCallUlt16
	jmp emit_compare_call
.unsignedLe:
	ldx #<exprCallUle16
	ldy #>exprCallUle16
	jmp emit_compare_call
.unsignedGt:
	ldx #<exprCallUgt16
	ldy #>exprCallUgt16
	jmp emit_compare_call

.equal:
	ldx #<exprCallEq16
	ldy #>exprCallEq16
	jmp emit_compare_call
.notEqual:
	ldx #<exprCallNe16
	ldy #>exprCallNe16
	jmp emit_compare_call

emit_compare_call:
	jsr emit_string
	bcs .newline
	rts
.newline:
	jsr emit_newline
	bcs .done
	rts
.done:
	jmp mark_expression_ax_truth

emit_jump_label:
	ldx #<exprJmp
	ldy #>exprJmp
	jsr emit_string
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

;;; Save a full index in NC_TMP and scale it for word elements. Direct byte/Y
;;; cases bypass this routine entirely.
emit_index_offset:
	jsr materialize_expression_word
	bcs .save
	rts
.save:
	jsr emit_save_right_tmp
	bcs .scale
	rts
.scale:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprScaleIndex
	ldy #>exprScaleIndex
	jmp emit_string
.done:
	sec
	rts

emit_index_address:
	jsr emit_index_offset
	bcs .base
	rts
.base:
	jsr materialize_saved_address
	bcs .call
	rts
.call:
	jmp emit_index_address_call

emit_index_address_call:
	lda #$01
	sta indexUsed
	ldx #<exprCallIndex16
	ldy #>exprCallIndex16
	jmp emit_string

;;; The target addressing mode is the representation. A byte index into char[]
;;; or char* stays in Y; only a wider index or word element constructs NC_PTR via
;;; __nc_index16.
emit_index_load:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .general
	jsr expression_index_is_byte_domain
	bcc .general
	jsr materialize_expression_byte
	bcs .toY
	rts
.toY:
	ldx #<exprTay
	ldy #>exprTay
	jsr emit_string
	bcs .baseKind
	rts
.baseKind:
	lda reduceLeftKind
	cmp #VALUE_ARRAY
	beq .fixedArray
	jsr materialize_saved_address
	bcs .savePtr
	rts
.savePtr:
	jsr emit_store_transient
	bcs .indirect
	rts
.indirect:
	ldx #<exprCharIndirectY
	ldy #>exprCharIndirectY
	jsr emit_string
	bcs .byteDone
	rts
.fixedArray:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .arrayName
	rts
.arrayName:
	ldx reduceLeftLow
	jsr emit_persistent_name
	bcs .arraySuffix
	rts
.arraySuffix:
	ldx #<exprIndexYSuffix
	ldy #>exprIndexYSuffix
	jsr emit_string
	bcs .byteDone
	rts
.byteDone:
	jmp mark_expression_a_truth

.general:
	jsr emit_index_address
	bcs .load
	rts
.load:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .char
	ldx #<exprWordIndirect
	ldy #>exprWordIndirect
	jsr emit_string
	bcs .wordDone
	rts
.wordDone:
	jmp mark_expression_ax
.char:
	ldx #<exprCharIndirectOnly
	ldy #>exprCharIndirectOnly
	jsr emit_string
	bcs .charDone
	rts
.charDone:
	jmp mark_expression_a_truth

expression_index_is_byte_domain:
	lda expressionValueType
	cmp #TYPE_CHAR
	beq .yes
	lda expressionValueKind
	cmp #VALUE_LITERAL
	bne .condition
	lda expressionValueHigh
	beq .yes
.condition:
	lda expressionValueKind
	cmp #VALUE_COND_EQ
	bcc .no
	cmp #VALUE_COND_LE+1
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

