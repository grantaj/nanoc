;;; expression_codegen_state.asm
;;;
;;; Scratch used only while formatting target assembly for expressions.
;;; None of this is expression-parser state: it exists only so the direct
;;; emitters can remember labels, a selected spill name and shift choices, plus
;;; the one short-lived physical condition fact described below and whether this
;;; translation needs target helpers.
;;;
;;; Source meaning stays elsewhere: expressionValueType is the C semantic type.
;;; Do not grow this into a generic value descriptor or register map.

;;; A live condition is named by the branch that observes target "true". NONE
;;; means the statement consumer must form truth from the materialised value.
;;; #88 will add the branch kinds it actually needs while changing comparison
;;; emission. BNE is enough for today's canonical 0/1 producer because its Z flag
;;; already says whether that materialised value is zero.
EXPR_CONDITION_NONE = 0
EXPR_CONDITION_BNE  = 1

emitSpillIndex:		byte 0
shiftLeftFlag:		byte 0
shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
compareDoneLabel:	word 0

;;; Both names deliberately denote the same byte. Existing comparison producers
;;; still spell the pre-#87 name; the statement consumer uses the physical branch
;;; contract now. #88 can remove the compatibility name as it rewrites those
;;; producers. This alias costs no state byte and avoids a mechanical churn PR.
expressionConditionBranch:
expressionTruthInZ:	byte EXPR_CONDITION_NONE

compareUsed:		byte 0
multiplyUsed:		byte 0
indexUsed:		byte 0
