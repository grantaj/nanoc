;;; expression_codegen_state.asm
;;;
;;; Scratch used only while spelling target assembly. Source meaning remains in
;;; expression.asm; these bytes are short-lived formatter facts, not an IR.

;;; Formatter scratch is established immediately before use. Keep it beside the
;;; expression machine in compiler work RAM rather than in the loaded image.
shiftLoopLabel              = $b3e8
shiftDoneLabel              = $b3ea
operandPrefix               = $b3ec

;;; A materialised canonical 0/1 may still have a useful Z flag. Direct byte CMP
;;; conditions are represented by VALUE_COND_* in expressionValueKind instead.
expressionConditionBranch   = $b3ee

compareUsed                 = $b3ef
multiplyUsed                = $b3f0
indexUsed                   = $b3f1
