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
	bcc .failed
	lda expressionValueLow
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprLdxImm
	ldy #>exprLdxImm
	jsr emit_string
	bcc .failed
	lda expressionValueHigh
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.failed:
	rts

emit_load_literal_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
	bcc .failed
	lda expressionValueLow
	jsr emit_literal_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcc .failed
	lda expressionValueLow
	jsr emit_literal_name
	bcc .failed
	jmp emit_newline
.failed:
	rts

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

;;; The C expression still has its promoted integer type. Only a proven final
;;; char consumer changes the physical width that this reduction must compute.
;;; Returns temporarily use the same statement marker as scalar assignments.
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
	bcc .failed
	jsr emit_arithmetic_carry
	bcc .failed
	jsr select_arithmetic_prefix
	jsr emit_right_low_operand
	bcc .failed
	jmp mark_expression_a
.savedRight:
	jsr materialize_expression_byte
	bcc .failed
	jsr emit_save_right_byte_tmp
	bcc .failed
	jsr materialize_saved_byte
	bcc .failed
	jsr emit_arithmetic_carry
	bcc .failed
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
	jmp mark_expression_a
.failed:
	rts

emit_word_arithmetic_reduction:
	jsr right_operand_is_direct
	bcc .savedRight
	jsr materialize_saved_word
	bcc .failed
	jsr emit_arithmetic_carry
	bcc .failed
	jsr select_arithmetic_prefix
	jsr emit_right_low_operand
	bcc .failed
	ldx #<exprTayTxa
	ldy #>exprTayTxa
	jsr emit_string
	bcc .failed
	jsr select_arithmetic_prefix
	jsr emit_right_high_operand
	bcc .failed
	ldx #<exprTaxTya
	ldy #>exprTaxTya
	jsr emit_string
	bcc .failed
	jmp mark_expression_ax

.savedRight:
	jsr materialize_expression_word
	bcc .failed
	jsr emit_save_right_tmp
	bcc .failed
	jsr materialize_saved_word
	bcc .failed
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
	jmp mark_expression_ax
.failed:
	rts

;;; Multiplication has the same lifetime split as ordinary arithmetic. A direct
;;; RHS has not disturbed a physical left value, so save the left in NC_TMP and
;;; spell the RHS directly. A computed RHS forced the parser to preserve its left
;;; operand already, so the commutative helper may save the RHS first instead.
;;; At a proven byte boundary, multiplication by low-byte 3 is simply A + 2*A.
emit_mul_reduction:
	jsr byte_result_is_final_scalar_assignment
	bcc .word
	lda reduceRightKind
	cmp #VALUE_LITERAL
	bne .word
	lda reduceRightLow
	cmp #$03
	bne .word
	jsr materialize_saved_byte
	bcc .failed
	jsr emit_save_right_byte_tmp
	bcc .failed
	;;; These are fixed prefixes of existing target text. Spell their byte counts
	;;; explicitly because native ass deliberately does not evaluate label-label
	;;; arithmetic in an immediate operand.
	lda #$0c			; "\tasl NC_TMP\n"
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jsr emit_text
	bcc .failed
	lda #$11			; "\tclc\n\tadc NC_TMP\n"
	ldx #<exprWordAddTmp
	ldy #>exprWordAddTmp
	jsr emit_text
	bcc .failed
	jmp mark_expression_a

.word:
	lda #$01
	sta multiplyUsed
	jsr right_operand_is_direct
	bcc .savedRight
	jsr materialize_saved_word
	bcc .failed
	jsr emit_save_right_tmp
	bcc .failed
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_right_low_operand
	bcc .failed
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_right_high_operand
	bcc .failed
	jmp .call
.savedRight:
	jsr materialize_expression_word
	bcc .failed
	jsr emit_save_right_tmp
	bcc .failed
	jsr materialize_saved_word
	bcc .failed
.call:
	ldx #<exprCallMul16
	ldy #>exprCallMul16
	jsr emit_string
	bcc .failed
	jmp mark_expression_ax
.failed:
	rts

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
	bcc .earlyFailed
	ldx #<exprShift8
	ldy #>exprShift8
	jsr emit_string
	bcc .earlyFailed
	jmp mark_expression_ax

.general:
	jsr materialize_expression_byte
	bcc .earlyFailed
	ldx #<exprTay
	ldy #>exprTay
	jsr emit_string
	bcc .earlyFailed
	jsr materialize_saved_word
	bcc .earlyFailed
	jsr emit_save_right_tmp
	bcc .earlyFailed
	jmp .labels
.earlyFailed:
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
	bcc .middleFailed
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_string
	bcc .middleFailed
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .middleFailed
	jsr emit_newline
	bcc .middleFailed
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .middleFailed
	jmp .body
.middleFailed:
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
	bcc .lateFailed
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_string
	bcc .lateFailed
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .lateFailed
	jsr emit_newline
	bcc .lateFailed
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .lateFailed
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jsr emit_string
	bcc .lateFailed
	jmp mark_expression_ax
.lateFailed:
	rts


;;; Comparisons/indexing and the emitted text vocabulary are kept beside the
;;; common arithmetic path without turning code generation into a framework.
	include "expression_compare_codegen.asm"
	include "expression_codegen_text.asm"
