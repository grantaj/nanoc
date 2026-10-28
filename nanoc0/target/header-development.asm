; Development seed compiler: built by real nanoc0, assembled after it exits.
; This image is NEVER assembled while the low-memory native assembler is live.
; Code $0800-$9fff (38 KiB); static C workspace $a000-$cfff (12 KiB).

	* = $0800
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
