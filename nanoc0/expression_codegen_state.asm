;;; expression_codegen_state.asm
;;;
;;; Code-generation state is declared with the expression work-RAM map in
;;; expression.asm, before this file can reference it. The routines below only
;;; interpret that small physical state; they do not introduce another IR.
