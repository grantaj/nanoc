;;; core.asm
;;;
;;; Size probe for the resident nanoc0 core.  These no-op output hooks let the
;;; scanner + declaration/symbol/storage implementation assemble without pulling
;;; in the later assembly writer.  `make nanoc0` reports the resulting resident
;;; byte count so compiler growth stays visible from the start.

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
