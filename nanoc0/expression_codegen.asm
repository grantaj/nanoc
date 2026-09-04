;;; expression_codegen.asm
;;;
;;; Direct target-code emission for expression.asm.
;;;
;;; There is deliberately no representation between the expression machine and
;;; these routines. A reduction calls the obvious emitter and ordinary `ass`
;;; source is streamed immediately. Fixed fragments below are the actual 6502
;;; sequences a reader would write by hand.

emit_load_literal:
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_string
	bcs .lowPrefix
	rts
.lowPrefix:
	lda expressionValueLow
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
	lda expressionValueHigh
	jsr emit_hex_byte
	bcs .done
	rts
.done:
	jmp emit_newline

emit_load_literal_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
	bcs .lowName
	rts
.lowName:
	lda expressionValueLow
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
	lda expressionValueLow
	jsr emit_literal_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_plus_one_newline:
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_string
	bcs .done
	rts
.done:
	jmp emit_newline

;;; NC_PTR/NC_TMP are the machine-contract scratch pairs. They are not C storage:
;;; use them only when a concrete operation really needs a transient pair.
emit_store_transient:
	ldx #<exprStorePtr
	ldy #>exprStorePtr
	jmp emit_string

emit_save_right_tmp:
	ldx #<exprSaveRight
	ldy #>exprSaveRight
	jmp emit_string

emit_save_right_byte_tmp:
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jmp emit_string

;;; X=current-function destination. Materialise only the width that destination
;;; can observe, then spell the direct store.
emit_store_current_value:
	;;; Name emitters use emitSavedIndex themselves, so keep the destination on
	;;; the compiler's hardware stack across operand materialisation instead of
	;;; inventing another persistent scratch byte for this short lifetime.
	txa
	pha
	lda currentType,x
	cmp #TYPE_CHAR
	bne .word
	jsr materialize_expression_byte
	bcs .prepared
	jmp .failed
.word:
	jsr materialize_expression_word
	bcs .prepared
	jmp .failed
.prepared:
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcs .lowName
	jmp .failed
.lowName:
	pla
	tax
	pha
	jsr emit_current_name
	bcs .lowDone
	jmp .failed
.lowDone:
	jsr emit_newline
	bcs .width
	jmp .failed
.width:
	pla
	tax
	pha
	lda currentType,x
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcs .highName
	jmp .failed
.highName:
	pla
	tax
	pha
	jsr emit_current_name
	bcs .highDone
	jmp .failed
.highDone:
	jsr emit_plus_one_newline
	bcc .failed
.done:
	pla
	tax
	sec
	rts
.failed:
	pla
	tax
	clc
	rts

emit_unary_minus:
	ldx #<exprNegate
	ldy #>exprNegate
	jsr emit_string
	bcs .done
	rts
.done:
	jmp mark_expression_ax

;;; ---------------------------------------------------------------------------
;;; Binary reductions
;;; ---------------------------------------------------------------------------

emit_binary_reduction:
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	lda reduceOperator
	cmp #OP_ADD
	beq .arithmetic
	cmp #OP_SUB
	beq .arithmetic
	cmp #OP_AND
	beq .arithmetic
	cmp #OP_OR
	beq .arithmetic
	cmp #OP_MUL
	beq .mul
	cmp #OP_SHL
	beq .shift
	cmp #OP_SHR
	beq .shift
	cmp #OP_LT
	bcc .bad
	cmp #OP_AND
	bcc .compare
.bad:
	clc
	rts
.arithmetic:
	jmp emit_arithmetic_reduction
.mul:
	jmp emit_mul_reduction
.shift:
	jmp emit_shift_reduction
.compare:
	jmp emit_compare_reduction

emit_arithmetic_reduction:
	jsr byte_result_is_final_scalar_assignment
	bcc .word
	jmp emit_byte_arithmetic_reduction
.word:
	jmp emit_word_arithmetic_reduction

emit_arithmetic_carry:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	sec
	rts
.add:
	ldx #<exprClc
	ldy #>exprClc
	jmp emit_string
.sub:
	ldx #<exprSec
	ldy #>exprSec
	jmp emit_string

select_arithmetic_prefix:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_AND
	beq .and
	ldx #<exprOraSpace
	ldy #>exprOraSpace
	rts
.add:
	ldx #<exprAdcSpace
	ldy #>exprAdcSpace
	rts
.sub:
	ldx #<exprSbcSpace
	ldy #>exprSbcSpace
	rts
.and:
	ldx #<exprAndSpace
	ldy #>exprAndSpace
	rts

emit_byte_arithmetic_reduction:
	jsr right_operand_is_direct
	bcc .savedRight
	jsr materialize_saved_byte
	bcs .directLeft
	rts
.directLeft:
	jsr emit_arithmetic_carry
	bcs .directOp
	rts
.directOp:
	jsr select_arithmetic_prefix
	jsr emit_right_low_operand
	bcs .done
	rts
.savedRight:
	jsr materialize_expression_byte
	bcs .save
	rts
.save:
	jsr emit_save_right_byte_tmp
	bcs .loadLeft
	rts
.loadLeft:
	jsr materialize_saved_byte
	bcs .carry
	rts
.carry:
	jsr emit_arithmetic_carry
	bcs .tmpOp
	rts
.tmpOp:
	lda reduceOperator
	cmp #OP_ADD
	beq .addTmp
	cmp #OP_SUB
	beq .subTmp
	cmp #OP_AND
	beq .andTmp
	ldx #<exprOraTmp
	ldy #>exprOraTmp
	jmp .emitTmp
.addTmp:
	ldx #<exprAdcTmp
	ldy #>exprAdcTmp
	jmp .emitTmp
.subTmp:
	ldx #<exprSbcTmp
	ldy #>exprSbcTmp
	jmp .emitTmp
.andTmp:
	ldx #<exprAndTmp
	ldy #>exprAndTmp
.emitTmp:
	jsr emit_string
	bcc .failed
.done:
	jmp mark_expression_a
.failed:
	clc
	rts

emit_word_arithmetic_reduction:
	jsr right_operand_is_direct
	bcc .savedRight
	jsr materialize_saved_word
	bcs .directCarry
	rts
.directCarry:
	jsr emit_arithmetic_carry
	bcs .directLow
	rts
.directLow:
	jsr select_arithmetic_prefix
	jsr emit_right_low_operand
	bcs .toHigh
	rts
.toHigh:
	ldx #<exprTayTxa
	ldy #>exprTayTxa
	jsr emit_string
	bcs .directHigh
	rts
.directHigh:
	jsr select_arithmetic_prefix
	jsr emit_right_high_operand
	bcs .finish
	rts
.finish:
	ldx #<exprTaxTya
	ldy #>exprTaxTya
	jsr emit_string
	bcs .done
	rts

.savedRight:
	jsr materialize_expression_word
	bcs .saveRight
	rts
.saveRight:
	jsr emit_save_right_tmp
	bcs .loadSaved
	rts
.loadSaved:
	jsr materialize_saved_word
	bcs .tmpChoice
	rts
.tmpChoice:
	lda reduceOperator
	cmp #OP_ADD
	beq .addTmp
	cmp #OP_SUB
	beq .subTmp
	cmp #OP_AND
	beq .andTmp
	ldx #<exprWordOrTmp
	ldy #>exprWordOrTmp
	jmp .emitTmp
.addTmp:
	ldx #<exprWordAddTmp
	ldy #>exprWordAddTmp
	jmp .emitTmp
.subTmp:
	ldx #<exprWordSubTmp
	ldy #>exprWordSubTmp
	jmp .emitTmp
.andTmp:
	ldx #<exprWordAndTmp
	ldy #>exprWordAndTmp
.emitTmp:
	jsr emit_string
	bcc .failed
.done:
	jmp mark_expression_ax
.failed:
	clc
	rts

;;; __nc_mul16 keeps the small frozen helper convention: left in NC_TMP, right
;;; in A/X, result in A/X. No static expression spill is involved.
emit_mul_reduction:
	lda #$01
	sta multiplyUsed
	jsr materialize_saved_word
	bcs .saveLeft
	rts
.saveLeft:
	jsr emit_save_right_tmp
	bcs .right
	rts
.right:
	;;; materialize_saved_word selected the left descriptor. The RHS identity is
	;;; still in reduceRight*, so restore it at the exact point the helper consumes it.
	lda reduceRightKind
	sta expressionValueKind
	lda reduceRightLow
	sta expressionValueLow
	lda reduceRightHigh
	sta expressionValueHigh
	lda reduceRightType
	sta expressionValueType
	jsr materialize_expression_word
	bcs .call
	rts
.call:
	ldx #<exprCallMul16
	ldy #>exprCallMul16
	jsr emit_string
	bcs .done
	rts
.done:
	jmp mark_expression_ax

emit_shift_reduction:
	;;; Exact logical >> 8 is simply the previous high byte.
	lda reduceOperator
	cmp #OP_SHR
	bne .general
	lda reduceRightKind
	cmp #VALUE_LITERAL
	bne .general
	lda reduceRightLow
	cmp #$08
	bne .general
	lda reduceRightHigh
	bne .general
	jsr materialize_saved_word
	bcs .shift8
	rts
.shift8:
	ldx #<exprShift8
	ldy #>exprShift8
	jsr emit_string
	bcs .shift8Done
	rts
.shift8Done:
	jmp mark_expression_ax

.general:
	jsr materialize_expression_byte
	bcs .countReady
	rts
.countReady:
	ldx #<exprTay
	ldy #>exprTay
	jsr emit_string
	bcs .left
	rts
.left:
	jsr materialize_saved_word
	bcs .saveLeft
	rts
.saveLeft:
	jsr emit_save_right_tmp
	bcs .labels
	rts
.labels:
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
	bcs .body
	rts
.body:
	lda reduceOperator
	cmp #OP_SHL
	bne .rightBody
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jmp .emitBody
.rightBody:
	ldx #<exprShiftRightBody
	ldy #>exprShiftRightBody
.emitBody:
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
	bcs .done
	rts
.done:
	jmp mark_expression_ax


;;; Comparisons/indexing and the emitted text vocabulary are kept beside the
;;; common arithmetic path without turning code generation into a framework.
	include "expression_compare_codegen.asm"
	include "expression_codegen_text.asm"
