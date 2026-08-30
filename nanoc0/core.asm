;;; core.asm
;;;
;;; Size probe for the resident nanoc0 core. These no-op output hooks let the
;;; scanner/declaration/expression implementation assemble without the eventual
;;; file-output runtime. `make nanoc0` keeps resident growth visible.

	* = $4000

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

;;; Compiler text sink contract: A=byte, carry set success; X/Y and $fc-$ff are
;;; preserved. The production sink arrives with the output runtime in #57.
emit_output_byte:
	sec
	rts

;;; Calls are deliberately not faked in #55. #57 replaces this hook with the
;;; explicit pending-call state machine.
expression_call_primary:
	clc
	rts

	include "declarations.asm"
