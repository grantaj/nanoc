	include "zp.inc"

	* = $c000

;;; Minimal parser demo. Walk sample source in place and reduce instructions to
;;; semantic instruction state until EOF.
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
	beq .done
	cmp #STATEMENT_INSTRUCTION
	bne .loop
	jsr parseInstruction
	jmp .loop
.done:
	rts

	include "parser.asm"
	include "instruction.asm"

INPUT:
	string "     \t\t; COMMENT"
	string "* = $C000"
	string "START:   "
	string "  \tLDA #$00 ; COMMENT"
	string "\tRTS"
	string "byte 0, 1, 2"
INPUT_END:
