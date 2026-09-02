;;; expression_codegen_state.asm
;;;
;;; Scratch used only while formatting target assembly for expressions.
;;; None of this is expression-parser state: it exists only so the direct
;;; emitters can remember labels, a selected spill name and shift choices, plus
;;; whether the current target Z flag already describes a comparison result and
;;; whether this translation needs the comparison or multiply target helpers.

emitSpillIndex:		byte 0
shiftLeftFlag:		byte 0
shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
compareDoneLabel:	word 0
expressionTruthInZ:	byte 0
compareUsed:		byte 0
multiplyUsed:		byte 0
