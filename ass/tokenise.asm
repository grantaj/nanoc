	include "zp.inc"
	CHROUT = $ffd2
	
;;; Token types
	
	LABEL = 1
	SYMBOL = 2
	DIRECTIVE = 3
	MNEMONIC = 4
	OPERAND = 5


	* = $c000

	lda #<INPUT
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1

.loop:
	ldy #$0
	lda (ZP_PTR1),y		; End of file marked with NULL
	bne .nextToken
	rts
	
.nextToken:	
	jsr skipWhitespace

	ldy #$0			; skip comments
	lda (ZP_PTR1),y
	cmp #';'
	beq .nextLine

	;; rest of token lexing goes here
	jsr printString
	lda #$d
	jsr CHROUT

.nextLine:
	;; Skip to the next line (byte after the next null)
	ldy #$0
	lda (ZP_PTR1),Y
	bne .increment
	
	inc ZP_PTR1		; skip the NULL
	bne .continue
	inc ZP_PTR1+1
	
.continue:
	jmp .loop
	
.increment:
	inc ZP_PTR1
	bne .nextLine
	inc ZP_PTR1+1
	jmp .nextLine
	
	include "printString.asm"
	include "skipws.asm"

;;; A made up program to test tokenisation
INPUT:
	string "     		; COMMENT"
	string "* = $C000"
	string "START:   "
	string "  	LDA #$00"
	string "	RTS"
	string ".BYTE 0, 1, 2"
	byte 0			; end of file
