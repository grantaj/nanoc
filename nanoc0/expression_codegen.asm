;;; expression_codegen.asm
;;;
;;; Direct target-code emission for expression.asm.
;;;
;;; There is deliberately no representation between the expression machine and
;;; these routines. A reduction calls the obvious emitter and ordinary `ass`
;;; source is streamed immediately. The only retained target facts are the small
;;; physical-value contract below: byte in A, word in A/X, or live comparison
;;; flags. Source meaning remains in expressionValueType.

EXPR_VALUE_BYTE      = 1
EXPR_VALUE_WORD      = 2
EXPR_VALUE_CONDITION = 3

EXPR_CONDITION_NONE = 0
EXPR_CONDITION_BNE  = 1
EXPR_CONDITION_BEQ  = 2
EXPR_CONDITION_BCC  = 3
EXPR_CONDITION_BCS  = 4

;;; ---------------------------------------------------------------------------
;;; Physical-value seam
;;; ---------------------------------------------------------------------------

mark_expression_byte_z:
	lda #EXPR_VALUE_BYTE
	sta expressionPhysicalKind
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	sec
	rts

narrow_expression_to_byte:
	lda #EXPR_VALUE_BYTE
	sta expressionPhysicalKind
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	sec
	rts

mark_expression_word:
	lda #EXPR_VALUE_WORD
	sta expressionPhysicalKind
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	sec
	rts

mark_expression_word_truth:
	lda #EXPR_VALUE_WORD
	sta expressionPhysicalKind
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	sec
	rts

;;; A is one EXPR_CONDITION_* branch that observes target true.
mark_expression_condition:
	sta expressionConditionBranch
	lda #EXPR_VALUE_CONDITION
	sta expressionPhysicalKind
	sec
	rts

;;; A byte can always be consumed from A. A complete word can be narrowed without
;;; emitted work; a lazy condition is materialised only because this consumer
;;; really asks for an integer value.
ensure_expression_byte_value:
	lda expressionPhysicalKind
	cmp #EXPR_VALUE_BYTE
	beq .ready
	cmp #EXPR_VALUE_WORD
	beq .narrow
	cmp #EXPR_VALUE_CONDITION
	beq materialize_expression_condition
	clc
	rts
.narrow:
	jmp narrow_expression_to_byte
.ready:
	sec
	rts

;;; Only a genuine word consumer asks for X. This is the one ordinary place where
;;; a physical byte is zero-extended.
ensure_expression_word:
	lda expressionPhysicalKind
	cmp #EXPR_VALUE_WORD
	beq .ready
	cmp #EXPR_VALUE_BYTE
	beq emit_zero_high
	cmp #EXPR_VALUE_CONDITION
	bne .bad
	jsr materialize_expression_condition
	bcc .bad
	jmp emit_zero_high
.ready:
	sec
	rts
.bad:
	clc
	rts

materialize_expression_value:
	lda expressionPhysicalKind
	cmp #EXPR_VALUE_CONDITION
	beq materialize_expression_condition
	cmp #EXPR_VALUE_BYTE
	beq .ready
	cmp #EXPR_VALUE_WORD
	beq .ready
	clc
	rts
.ready:
	sec
	rts

;;; A comparison-as-value is rare enough that the obvious local control sequence
;;; is preferable to a second Boolean representation. The live flags are consumed
;;; by the first branch; only then do we manufacture canonical 0/1 in A.
materialize_expression_condition:
	lda #EMIT_LABEL_CMP_DONE
	sta emitLabelKind
	jsr reserve_generated_label
	lda emitLabelValue
	sta conditionTrueLabel
	lda emitLabelValue+1
	sta conditionTrueLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareDoneLabel
	lda emitLabelValue+1
	sta compareDoneLabel+1

	lda expressionConditionBranch
	cmp #EXPR_CONDITION_BNE
	beq .bne
	cmp #EXPR_CONDITION_BEQ
	beq .beq
	cmp #EXPR_CONDITION_BCC
	beq .bcc
	cmp #EXPR_CONDITION_BCS
	beq .bcs
	clc
	rts
.bne:
	ldx #<exprBne
	ldy #>exprBne
	jmp .branch
.beq:
	ldx #<exprBeq
	ldy #>exprBeq
	jmp .branch
.bcc:
	ldx #<exprBcc
	ldy #>exprBcc
	jmp .branch
.bcs:
	ldx #<exprBcs
	ldy #>exprBcs
.branch:
	jsr emit_string
	bcc .failed
	lda conditionTrueLabel
	sta emitLabelValue
	lda conditionTrueLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed

	ldx #<exprByteFalse
	ldy #>exprByteFalse
	jsr emit_string
	bcc .failed
	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed

	lda conditionTrueLabel
	sta emitLabelValue
	lda conditionTrueLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .failed
	ldx #<exprByteTrue
	ldy #>exprByteTrue
	jsr emit_string
	bcc .failed

	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .failed
	jmp mark_expression_byte_z
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Primary values and storage
;;; ---------------------------------------------------------------------------

emit_load_literal:
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_string
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
	ldx #<exprLdxImm
	ldy #>exprLdxImm
	jsr emit_string
	bcs .highPrefix
	rts
.highPrefix:
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcs .done
	rts
.done:
	jsr emit_newline
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_load_literal_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
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
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcs .highName
	rts
.highName:
	lda currentLiteralIndex
	jsr emit_literal_name
	bcs .done
	rts
.done:
	jsr emit_newline
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

;;; Load the scalar captured by expression.asm. During a direct scalar reduction
;;; A still holds the left operand, so deliberately emit no target load; the
;;; direct reducer addresses this symbol in place.
emit_load_primary_scalar:
	lda immediateBinaryState
	cmp #IMMEDIATE_BINARY_CAPTURED_SCALAR
	bne .emit
	lda emitSpillIndex
	cmp #EMIT_TRANSIENT_SPILL
	bne .emit
	jsr scalar_operator_is_direct
	bcc .emit
	sec
	rts

.emit:
emit_load_primary_scalar_now:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .lowName
	rts
.lowName:
	jsr emit_primary_scalar_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .width
	rts
.width:
	lda primarySymbolType
	cmp #TYPE_CHAR
	bne .word
	jmp mark_expression_byte_z
.word:
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcs .highName
	rts
.highName:
	jsr emit_primary_scalar_name
	bcs .highDone
	rts
.highDone:
	jsr emit_plus_one_newline
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_zero_high:
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_load_primary_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
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
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcs .highName
	rts
.highName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .done
	rts
.done:
	jsr emit_newline
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_plus_one_newline:
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_string
	bcs .done
	rts
.done:
	jmp emit_newline

;;; Spill storage remains a conservative word lifetime in #88. The important
;;; change is that ordinary byte values do not become words merely because they
;;; were loaded; widening happens here only when a later expression must survive.
emit_spill_definition:
	sta emitSpillIndex
	jsr emit_spill_name
	bcs .assign
	rts
.assign:
	ldx #<exprBssAssign
	ldy #>exprBssAssign
	jsr emit_string
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

;;; Internal address code already knows A/X is a pair. Do not consult expression
;;; state here: the current expression may be saved elsewhere while an lvalue
;;; address is being restored.
emit_store_transient:
	lda #EMIT_TRANSIENT_SPILL
	sta emitSpillIndex
	jmp emit_store_spill_pair

;;; A simple scalar RHS which the target instruction can address directly needs
;;; no transient spill at all.
emit_store_spill:
	sta emitSpillIndex
	cmp #EMIT_TRANSIENT_SPILL
	bne .store
	jsr scalar_operator_is_direct
	bcc .store
	sec
	rts
.store:
emit_store_spill_now:
	jsr ensure_expression_word
	bcc .failed
emit_store_spill_pair:
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
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
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcs .highName
	rts
.highName:
	lda emitSpillIndex
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline
.failed:
	clc
	rts

;;; X=current-function symbol index. The destination, not the source C type,
;;; decides how much physical value is observable.
emit_store_current_value:
	stx emitSavedIndex
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	bne .word
	jsr ensure_expression_byte_value
	jmp .prepared
.word:
	jsr ensure_expression_word
.prepared:
	bcc .failedRestore
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcs .lowName
	jmp .failedRestore
.lowName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .lowDone
	jmp .failedRestore
.lowDone:
	jsr emit_newline
	bcs .width
	jmp .failedRestore
.width:
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcs .highName
	jmp .failedRestore
.highName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .highDone
	jmp .failedRestore
.highDone:
	jsr emit_plus_one_newline
	bcc .failedRestore
.done:
	ldx emitSavedIndex
	sec
	rts
.failedRestore:
	ldx emitSavedIndex
	clc
	rts

emit_unary_minus:
	jsr ensure_expression_word
	bcc .failed
	ldx #<exprNegate
	ldy #>exprNegate
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Binary reductions
;;; ---------------------------------------------------------------------------

emit_binary_reduction:
	lda reduceSpill
	cmp #EMIT_TRANSIENT_SPILL
	bne .ordinary
	jsr scalar_operator_is_direct
	bcc .ordinary
	jmp emit_scalar_binary_reduction

.ordinary:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_MUL
	beq .mul
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
	cmp #OP_SHL
	beq .shl
	cmp #OP_SHR
	beq .shr
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
	jmp emit_add_reduction
.sub:
	jmp emit_sub_reduction
.mul:
	jmp emit_mul_reduction
.and:
	jmp emit_and_reduction
.or:
	jmp emit_or_reduction
.shl:
	jmp emit_shl_reduction
.shr:
	jmp emit_shr_reduction
.compare:
	jmp emit_compare_reduction

;;; A/X is the right operand. Preserve exactly the width the reduction needs.
emit_save_right_tmp:
	jsr ensure_expression_word
	bcc .failed
	ldx #<exprSaveRight
	ldy #>exprSaveRight
	jmp emit_string
.failed:
	clc
	rts

emit_save_right_byte_tmp:
	jsr ensure_expression_byte_value
	bcc .failed
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jmp emit_string
.failed:
	clc
	rts

emit_lda_reduce_spill:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
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
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
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
	ldx #<exprAddLow
	ldy #>exprAddLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .addHigh
	rts
.addHigh:
	ldx #<exprAddHigh
	ldy #>exprAddHigh
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_sub_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .subLow
	rts
.subLow:
	ldx #<exprSubLow
	ldy #>exprSubLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .subHigh
	rts
.subHigh:
	ldx #<exprSubHigh
	ldy #>exprSubHigh
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_and_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .andLow
	rts
.andLow:
	ldx #<exprAndLow
	ldy #>exprAndLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .andHigh
	rts
.andHigh:
	ldx #<exprAndHigh
	ldy #>exprAndHigh
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_or_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .orLow
	rts
.orLow:
	ldx #<exprOrLow
	ldy #>exprOrLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .orHigh
	rts
.orHigh:
	ldx #<exprOrHigh
	ldy #>exprOrHigh
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

;;; __nc_mul16 uses the frozen helper convention: left operand in NC_TMP,
;;; right operand in A/X, result in A/X.
emit_mul_reduction:
	jsr ensure_expression_word
	bcc .failed
	lda #$01
	sta multiplyUsed
	ldx #<exprMulSaveLow
	ldy #>exprMulSaveLow
	jsr emit_string
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .tail
	rts
.tail:
	ldx #<exprMulTail
	ldy #>exprMulTail
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_shl_reduction:
	lda #$01
	sta shiftLeftFlag
	jmp emit_shift_reduction

emit_shr_reduction:
	lda #$00
	sta shiftLeftFlag

;;; Variable shifts retain their existing small generated loop. The count uses
;;; the same low-byte convention as before; if it is a lazy comparison it must be
;;; materialised before TAY consumes A.
emit_shift_reduction:
	jsr ensure_expression_byte_value
	bcc .failed
	lda #EMIT_LABEL_GENERIC
	sta emitLabelKind
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

	ldx #<exprShiftCount
	ldy #>exprShiftCount
	jsr emit_string
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .saveHigh
	rts
.saveHigh:
	ldx #<exprStaTmpHigh
	ldy #>exprStaTmpHigh
	jsr emit_string
	bcs .zeroCheck
	rts
.zeroCheck:
	ldx #<exprCpyZero
	ldy #>exprCpyZero
	jsr emit_string
	bcs .zeroBranch
	rts
.zeroBranch:
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_string
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
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jmp .body
.right:
	ldx #<exprShiftRightBody
	ldy #>exprShiftRightBody
.body:
	jsr emit_string
	bcs .loopBranch
	rts
.loopBranch:
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_string
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
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Comparisons
;;; ---------------------------------------------------------------------------

;;; Statement destinations may be arbitrarily far away. For those real semantic
;;; jumps, branch over one adjacent absolute JMP so the relative branch remains
;;; local without any distance analysis.
emit_long_conditional_jump:
	stx conditionalBranchPtr
	sty conditionalBranchPtr+1
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

	ldx conditionalBranchPtr
	ldy conditionalBranchPtr+1
	jsr emit_string
	bcs .skipName
	rts
.skipName:
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .branchDone
	jmp .restoreFailed
.branchDone:
	jsr emit_newline
	bcs .jump
	jmp .restoreFailed
.jump:
	lda conditionalTargetKind
	sta emitLabelKind
	lda conditionalTargetLabel
	sta emitLabelValue
	lda conditionalTargetLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcs .skipLabel
	jmp .restoreFailed
.skipLabel:
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	php
	lda conditionalTargetKind
	sta emitLabelKind
	plp
	rts
.restoreFailed:
	lda conditionalTargetKind
	sta emitLabelKind
	clc
	rts

;;; Byte comparisons leave the useful target flags live. Wider comparisons keep
;;; the existing helper convention, which already returns canonical 0/1 in A/X
;;; and leaves Z matching A.
emit_compare_reduction:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .word
	lda reduceRightType
	cmp #TYPE_CHAR
	bne .word
	jmp emit_byte_compare_reduction
.word:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_ldx_reduce_spill_high
	bcs .call
	rts
.call:
	jmp emit_compare_helper_call

emit_byte_compare_reduction:
	lda reduceOperator
	cmp #OP_EQ
	beq .equality
	cmp #OP_NE
	beq .equality
	cmp #OP_GT
	beq .rightAgainstLeft
	cmp #OP_LE
	beq .rightAgainstLeft

	jsr emit_save_right_byte_tmp
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_string
	bcc .failed
	lda reduceOperator
	cmp #OP_GE
	beq .ge
	lda #EXPR_CONDITION_BCC
	jmp mark_expression_condition
.ge:
	lda #EXPR_CONDITION_BCS
	jmp mark_expression_condition

.rightAgainstLeft:
	jsr ensure_expression_byte_value
	bcc .failed
	jsr emit_cmp_reduce_spill
	bcc .failed
	lda reduceOperator
	cmp #OP_LE
	beq .le
	lda #EXPR_CONDITION_BCC
	jmp mark_expression_condition
.le:
	lda #EXPR_CONDITION_BCS
	jmp mark_expression_condition

.equality:
	jsr ensure_expression_byte_value
	bcc .failed
	jsr emit_cmp_reduce_spill
	bcc .failed
	lda reduceOperator
	cmp #OP_EQ
	bne .ne
	lda #EXPR_CONDITION_BEQ
	jmp mark_expression_condition
.ne:
	lda #EXPR_CONDITION_BNE
	jmp mark_expression_condition
.failed:
	clc
	rts

emit_cmp_reduce_spill:
	ldx #<exprCmpSpace
	ldy #>exprCmpSpace
	jsr emit_string
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_cmp_literal_byte:
	ldx #<exprCmpImmediate
	ldy #>exprCmpImmediate
	jsr emit_string
	bcs .value
	rts
.value:
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcs .done
	rts
.done:
	jmp emit_newline

emit_byte_false_result:
	ldx #<exprByteFalse
	ldy #>exprByteFalse
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z
.failed:
	clc
	rts

emit_byte_true_result:
	ldx #<exprByteTrue
	ldy #>exprByteTrue
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z
.failed:
	clc
	rts

;;; A/X is already the left operand and NC_TMP is the right operand.
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
	bcc .failed
	jmp mark_expression_word_truth
.failed:
	clc
	rts

emit_ldx_reduce_spill_high:
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

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

;;; ---------------------------------------------------------------------------
;;; Indexing
;;; ---------------------------------------------------------------------------

emit_index_offset:
	lda #$01
	sta indexUsed
	jsr emit_save_right_tmp
	bcc .failed
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprScaleIndex
	ldy #>exprScaleIndex
	jmp emit_string
.done:
	sec
	rts
.failed:
	clc
	rts

emit_index_address:
	jsr emit_index_offset
	bcc .failed
	lda reduceSpill
	cmp #INDEX_ARRAY_BIAS
	bcc .spilled
	sec
	sbc #INDEX_ARRAY_BIAS
	sta primarySymbolIndex
	jsr emit_load_primary_address
	jmp .call
.spilled:
	jsr emit_lda_reduce_spill
	bcc .failed
	jsr emit_ldx_reduce_spill_high
.call:
	bcs emit_index_address_call
.failed:
	clc
	rts

emit_index_address_call:
	ldx #<exprCallIndex16
	ldy #>exprCallIndex16
	jmp emit_string

emit_index_load:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .general
	lda expressionValueType
	cmp #TYPE_CHAR
	bne .general

	;;; Byte indexes belong in Y. Fixed arrays use absolute,Y directly. Pointer
	;;; values were already saved before the index expression.
	jsr ensure_expression_byte_value
	bcc .failed
	ldx #<exprTay
	ldy #>exprTay
	jsr emit_string
	bcc .failed
	lda reduceSpill
	cmp #INDEX_ARRAY_BIAS
	bcs .fixedArray
	jsr emit_lda_reduce_spill
	bcc .failed
	jsr emit_ldx_reduce_spill_high
	bcc .failed
	jsr emit_store_transient
	bcc .failed
	ldx #<exprCharIndirectY
	ldy #>exprCharIndirectY
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z

.fixedArray:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcc .failed
	lda reduceSpill
	sec
	sbc #INDEX_ARRAY_BIAS
	tax
	jsr emit_persistent_name
	bcc .failed
	ldx #<exprIndexYSuffix
	ldy #>exprIndexYSuffix
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z

.general:
	jsr emit_index_address
	bcc .failed
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .char
	ldx #<exprWordIndirect
	ldy #>exprWordIndirect
	jsr emit_string
	bcc .failed
	jmp mark_expression_word
.char:
	ldx #<exprCharIndirect
	ldy #>exprCharIndirect
	jsr emit_string
	bcc .failed
	jmp mark_expression_byte_z
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed target-source fragments
;;; ---------------------------------------------------------------------------

exprLdaImm:		byte $09,'l','d','a',' ','#','$'
exprLdaImmEnd:		byte 0
exprLdxImm:		byte $09,'l','d','x',' ','#','$'
exprLdxImmEnd:		byte 0
exprLdaLowImm:		byte $09,'l','d','a',' ','#','<'
exprLdaLowImmEnd:	byte 0
exprLdxHighImm:		byte $09,'l','d','x',' ','#','>'
exprLdxHighImmEnd:	byte 0
exprLdaSpace:		byte $09,'l','d','a',' '
exprLdaSpaceEnd:		byte 0
exprLdxSpace:		byte $09,'l','d','x',' '
exprLdxSpaceEnd:		byte 0
exprStaSpace:		byte $09,'s','t','a',' '
exprStaSpaceEnd:		byte 0
exprStxSpace:		byte $09,'s','t','x',' '
exprStxSpaceEnd:		byte 0
exprLdxZero:		byte $09,'l','d','x',' ','#','$','0','0',$0a
exprLdxZeroEnd:		byte 0
exprPlusOne:		byte '+','1'
exprPlusOneEnd:		byte 0
exprBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
exprBssAssignEnd:	byte 0
exprBytePrefix:		byte $09,'b','y','t','e',' '
exprBytePrefixEnd:	byte 0

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
exprNegateEnd:		byte 0

exprSaveRight:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
exprSaveRightEnd:	byte 0
exprAddLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAddLowEnd:		byte 0
exprAddHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAddHighEnd:		byte 0
exprSubLow:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprSubLowEnd:		byte 0
exprSubHigh:
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprSubHighEnd:		byte 0
exprAndLow:
	byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAndLowEnd:		byte 0
exprAndHigh:
	byte $09,'a','n','d',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAndHighEnd:		byte 0
exprOrLow:
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprOrLowEnd:		byte 0
exprOrHigh:
	byte $09,'o','r','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprOrHighEnd:		byte 0

exprTay:
exprMulSaveLow:		byte $09,'t','a','y',$0a
exprMulSaveLowEnd:	byte 0
exprStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
exprStaTmpEnd:		byte 0
exprStaTmpHigh:		byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
exprStaTmpHighEnd:	byte 0
exprMulTail:
	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','y','a',$0a
	byte $09,'j','s','r',' ','_','_','n','c','_','m','u','l','1','6',$0a
exprMulTailEnd:		byte 0

exprShiftCount:		byte $09,'t','a','y',$0a
exprShiftCountEnd:	byte 0
exprCpyZero:		byte $09,'c','p','y',' ','#','$','0','0',$0a
exprCpyZeroEnd:		byte 0
exprShiftLeftBody:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'d','e','y',$0a
exprShiftLeftBodyEnd:	byte 0
exprShiftRightBody:
	byte $09,'l','s','r',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','T','M','P',$0a
	byte $09,'d','e','y',$0a
exprShiftRightBodyEnd:	byte 0
exprLoadTmpResult:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','x',' ','N','C','_','T','M','P','+','1',$0a
exprLoadTmpResultEnd:	byte 0

exprCmpSpace:		byte $09,'c','m','p',' ',0
exprCmpImmediate:	byte $09,'c','m','p',' ','#','$',0
exprCmpTmp:		byte $09,'c','m','p',' ','N','C','_','T','M','P',$0a,0
exprByteFalse:		byte $09,'l','d','a',' ','#','$','0','0',$0a,0
exprByteTrue:		byte $09,'l','d','a',' ','#','$','0','1',$0a,0

exprBne:		byte $09,'b','n','e',' '
exprBneEnd:		byte 0
exprBeq:		byte $09,'b','e','q',' '
exprBeqEnd:		byte 0
exprBcc:		byte $09,'b','c','c',' '
exprBccEnd:		byte 0
exprBcs:		byte $09,'b','c','s',' '
exprBcsEnd:		byte 0
exprJmp:		byte $09,'j','m','p',' '
exprJmpEnd:		byte 0
exprCallEq16:		byte $09
			string "jsr __nc_eq16"
exprCallNe16:		byte $09
			string "jsr __nc_ne16"
exprCallSlt16:		byte $09
			string "jsr __nc_slt16"
exprCallSle16:		byte $09
			string "jsr __nc_sle16"
exprCallSgt16:		byte $09
			string "jsr __nc_sgt16"
exprCallSge16:		byte $09
			string "jsr __nc_sge16"
exprCallUlt16:		byte $09
			string "jsr __nc_ult16"
exprCallUle16:		byte $09
			string "jsr __nc_ule16"
exprCallUgt16:		byte $09
			string "jsr __nc_ugt16"
exprCallUge16:		byte $09
			string "jsr __nc_uge16"
exprCallIndex16:
	byte $09,'j','s','r',' ','_','_','n','c','_','i','n','d','e','x','1','6',$0a,0

exprScaleIndex:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
exprScaleIndexEnd:	byte 0
exprCharIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
exprCharIndirectY:
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a,0
exprCharIndirectEnd:	byte 0
exprIndexYSuffix:	byte ',', 'y', $0a, 0
exprWordIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'t','a','x',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
exprWordIndirectEnd:	byte 0

;;; Scratch used only while formatting a branch-over-JMP statement transfer.
conditionalBranchPtr:		word 0
conditionalTargetLabel:	word 0
conditionalSkipLabel:		word 0
conditionalTargetKind:	byte EMIT_LABEL_GENERIC
