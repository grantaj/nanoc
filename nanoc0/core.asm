;;; core.asm
;;;
;;; Size probe for the resident nanoc0 core. Declaration/static-data hooks are
;;; no-ops here; expression text is discarded because emitOutputEnabled defaults
;;; to zero. `make nanoc0` keeps resident compiler growth visible.

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

	include "declarations.asm"
