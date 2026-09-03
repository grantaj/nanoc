;;; expression_codegen_state.asm
;;;
;;; Scratch used only while spelling target assembly. Source meaning remains in
;;; expression.asm; these bytes are short-lived formatter facts, not an IR.

EXPR_CONDITION_NONE = 0
EXPR_CONDITION_BNE  = 1

shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
operandPrefix:		word 0

;;; A materialised canonical 0/1 may still have a useful Z flag. Direct byte CMP
;;; conditions are represented by VALUE_COND_* in expressionValueKind instead.
expressionConditionBranch:	byte EXPR_CONDITION_NONE

compareUsed:		byte 0
multiplyUsed:		byte 0
indexUsed:		byte 0
