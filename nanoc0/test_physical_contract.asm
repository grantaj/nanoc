	include "../test.inc"

PC_FAIL_NONE    = $01
PC_FAIL_BRANCH  = $02
PC_FAIL_DEFER   = $03
PC_FAIL_INVALID = $04

;;; This is a seam test, not a second expression evaluator. It calls the real
;;; statement emitter with output disabled and checks only the tiny physical
;;; condition state introduced by #87.
	* = $4000

main:
	lda #$00
	sta emitOutputEnabled
	jsr reset_generated_labels

	;;; No live condition: an ordinary byte value in A must still be accepted and
	;;; the production emitter forms its truth test before the branch.
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	lda #VALUE_A
	sta expressionValueKind
	lda #TYPE_CHAR
	sta expressionValueType
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .branchState
	lda #PC_FAIL_NONE
	jmp pc_finish

.branchState:
	;;; A live BNE=true condition is already sufficient physical state for the
	;;; same production control-flow emitter.
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	lda #TYPE_INT
	sta expressionValueType
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .alias
	lda #PC_FAIL_BRANCH
	jmp pc_finish

.alias:
	;;; A deferred named byte is a complete physical operand state. The production
	;;; control-flow emitter materialises it only at this consumer boundary.
	lda #VALUE_CURRENT
	sta expressionValueKind
	lda #TYPE_CHAR
	sta expressionValueType
	lda #$00
	sta expressionValueLow
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .invalid
	lda #PC_FAIL_DEFER
	jmp pc_finish

.invalid:
	;;; Unknown physical state must fail closed instead of silently meaning BNE.
	lda #$7f
	sta expressionConditionBranch
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcc .pass
	lda #PC_FAIL_INVALID
	jmp pc_finish

.pass:
	lda #TEST_PASS
pc_finish:
	sta TEST_RESULT
.halt:
	jmp .halt

pc_prepare_target:
	lda #EMIT_LABEL_GENERIC
	sta emitLabelKind
	lda #$01
	sta emitLabelValue
	lda #$00
	sta emitLabelValue+1
	rts

;;; declarations.asm references these production output hooks even though this
;;; seam test never parses a declaration. Keep them as the ordinary no-op test
;;; hooks rather than carrying a private parser/emitter copy.
emit_persistent_symbol:
	sec
	rts
emit_current_symbol:
	sec
	rts
emit_static_byte:
	sec
	rts
emit_bss_boundaries:
	sec
	rts

	include "declarations.asm"
