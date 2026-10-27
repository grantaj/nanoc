;;; Bootstrap target map for the first C-written compiler.
;;;
;;; nanoc1 is intentionally allowed to use the 24 KiB low-resident window already
;;; used by the native bootstrap ladder.  Its static workspace lives under BASIC.
;;; The public entry owns that memory-map change and restores the caller's map.

	* = $4000
NC_TMP = $fc
NC_PTR = $fe
NC_BSS = $a000

__nc_start:
	lda $01
	pha
	lda #$36
	sta $01
	jsr __nc_entry
	sta NC_TMP
	stx NC_TMP+1
	pla
	sta $01
	lda NC_TMP
	ldx NC_TMP+1
	rts
