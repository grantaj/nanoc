;;; Fixed prelude for nanoc1-generated Phase 1 translation units.
;;;
;;; #100 deliberately keeps the same simple machine contract as nanoc0.  The
;;; successor optimisation work in #102 may change how values reach this contract,
;;; but the semantic compiler has no hidden runtime representation.

	* = $0800
NC_TMP = $fc
NC_PTR = $fe
NC_BSS = $4800

__nc_start:
	jmp __nc_entry