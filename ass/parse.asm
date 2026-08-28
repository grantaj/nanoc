	include "zp.inc"

	* = $c000

;;; Minimal parser demo. Walk the sample source in place until EOF.
main:
	lda #<INPUT
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1
	lda #<INPUT_END
	sta sourceEnd
	lda #>INPUT_END
	sta sourceEnd+1

.loop:
	jsr nextStatement
	cmp #STATEMENT_EOF
	bne .loop
	rts

	include "parser.asm"

INPUT:
	string "     \t\t; COMMENT"
	string "* = $C000"
	string "START:   "
	string "  \tLDA #$00 ; COMMENT"
	string "\tRTS"
	string ".BYTE 0, 1, 2"
INPUT_END:
