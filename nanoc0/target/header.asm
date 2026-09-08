;;; Fixed prelude for every Nano C generated translation unit.
;;;
;;; This is target assembly, not compiler state. Keeping it here avoids carrying
;;; a second text copy in resident nanoc0 while leaving the machine map explicit.

	* = $0800
NC_TMP = $fc
NC_PTR = $fe
NC_BSS = $4800

__nc_start:
	jmp __nc_entry
