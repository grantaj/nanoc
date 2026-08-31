;;; expression_codegen_state.asm
;;;
;;; Scratch used only while formatting target assembly for expressions.
;;; None of this is expression-parser state: it exists only so the direct
;;; emitters can remember labels, a selected spill name, comparison/shift
;;; choices, and whether this translation needs the private multiply helper.

emitSpillIndex:		byte 0
shiftLeftFlag:		byte 0
shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
compareTrueLabel:	word 0
compareFalseLabel:	word 0
compareDoneLabel:	word 0
compareSameSignLabel:	word 0
compareInvert:		byte 0
multiplyUsed:		byte 0
