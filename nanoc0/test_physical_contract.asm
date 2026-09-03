	include "../test.inc"

PC_FAIL_NONE    = $01
PC_FAIL_BNE     = $02
PC_FAIL_BEQ     = $03
PC_FAIL_BCC     = $04
PC_FAIL_BCS     = $05
PC_FAIL_INVALID = $06

;;; This is a seam test, not a second expression evaluator. It calls the real
;;; statement emitter with output disabled and checks only the small physical
;;; value/condition facts shared by the production expression and statement code.
	* = $4000

main:
	lda #$00
	sta emitOutputEnabled
	jsr reset_generated_labels

	;;; No live condition: an ordinary byte value must still be accepted and the
	;;; production emitter forms truth from its physical width.
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	lda #EXPR_VALUE_BYTE
	sta expressionPhysicalKind
	lda #TYPE_CHAR
	sta expressionValueType
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .bne
	lda #PC_FAIL_NONE
	jmp pc_finish

.bne:
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	lda #EXPR_VALUE_CONDITION
	sta expressionPhysicalKind
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .beq
	lda #PC_FAIL_BNE
	jmp pc_finish

.beq:
	lda #EXPR_CONDITION_BEQ
	sta expressionConditionBranch
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .bcc
	lda #PC_FAIL_BEQ
	jmp pc_finish

.bcc:
	lda #EXPR_CONDITION_BCC
	sta expressionConditionBranch
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .bcs
	lda #PC_FAIL_BCC
	jmp pc_finish

.bcs:
	lda #EXPR_CONDITION_BCS
	sta expressionConditionBranch
	jsr pc_prepare_target
	jsr emit_statement_false_jump
	bcs .invalid
	lda #PC_FAIL_BCS
	jmp pc_finish

.invalid:
	;;; Unknown physical state must fail closed instead of silently choosing a
	;;; plausible branch instruction.
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
