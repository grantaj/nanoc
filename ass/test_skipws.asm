	include "zp.inc"
	CHROUT = $FFD2
	
	* = $c000
	
	lda #<STRPTR
	sta ZP_PTR1
	lda #>STRPTR
	sta ZP_PTR1+1
	
	jsr printString

	lda #$d
	jsr CHROUT
	
	jsr skipWhitespace

	jsr printString

	lda #$d
	jsr CHROUT

	rts
	
STRPTR:	
	string "   STRING WITH LEADING WHITESPACE"

	include "printString.asm"
	include "skipws.asm"
