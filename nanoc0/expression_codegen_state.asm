;;; expression_codegen_state.asm
;;;
;;; Scratch used only while formatting target assembly for expressions.
;;; None of this is expression-parser state: it exists only so the direct
;;; emitters can remember labels, a selected spill name and shift choices, plus
;;; the tiny physical-value facts defined by expression_codegen.asm and whether
;;; this translation needs target helpers.
;;;
;;; Source meaning stays elsewhere: expressionValueType is the C semantic type.
;;; Do not grow this into a generic value descriptor or register map.

emitSpillIndex:		byte 0
shiftLeftFlag:		byte 0
shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
compareDoneLabel:	word 0
conditionTrueLabel:	word 0

;;; The physical kind says only what the immediately generated target code has
;;; left live: a byte in A, a complete word in A/X, or comparison flags whose C
;;; 0/1 value has not yet been manufactured. The branch byte names which branch
;;; observes true while those flags remain live.
expressionPhysicalKind:	byte EXPR_VALUE_WORD
expressionConditionBranch:	byte EXPR_CONDITION_NONE

compareUsed:		byte 0
multiplyUsed:		byte 0
indexUsed:		byte 0
