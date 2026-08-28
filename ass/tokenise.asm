	include "zp.inc"
	CHROUT = $ffd2

	* = $c000

;;; Tokeniser demo program

	lda #<INPUT		; source cursor
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1

	lda #<INPUT_END		; one byte past source buffer
	sta sourceEnd
	lda #>INPUT_END
	sta sourceEnd+1

	lda #<TOKENS		; token output cursor
	sta ZP_PTR0
	lda #>TOKENS
	sta ZP_PTR0+1

	jsr tokenise

	;; output tokens
	lda #<TOKENS
	sta ZP_PTR0
	lda #>TOKENS
	sta ZP_PTR0+1

.nextTokenChar:
	lda (ZP_PTR0),Y
	beq .tokenType       	; Null-terminator check
	jsr CHROUT
	inc ZP_PTR0
	bne .nextTokenChar	; Keep printing if not page boundary
	inc ZP_PTR0+1     	; Handle page crossing
	jmp .nextTokenChar

.tokenType:
	inc ZP_PTR0
	bne .nextTokenChar	; Keep printing if not page boundary
	inc ZP_PTR0+1     	; Handle page crossing
	lda #' '
	jsr CHROUT
.getTokenType:
	lda (ZP_PTR0),y
	cmp #$FF
	bne .printTokenString
	jmp .exit

.printTokenString:
	asl			; token strings are 10 bytes including NULL
	asl			; multiply token type number by 10
	asl
	clc
	adc (ZP_PTR0),y
	adc (ZP_PTR0),y

	tay
	lda #<tokenStrings
	sta ZP_PTR1
	lda #>tokenStrings
	sta ZP_PTR1+1
	jsr printString
	lda #$0d
	jsr CHROUT
	jmp .nextTokenChar

.exit:
	rts

	include "printString.asm"
	include "tokeniser.asm"

;;; Token Strings Array
tokenStrings:
	string "LABEL"
	byte 0,0,0,0
	string "SYMBOL"
	byte 0,0
	string "DIRECTIVE"
	string "MNEMONIC"
	byte 0
	string "OPERAND"
	byte 0,0,0
	string "EQUALS"
	byte 0,0,0,0

;;; A made up program to test tokenisation.
;;; Each string directive contributes the NUL that terminates its source line.
INPUT:
	string "     \t\t; COMMENT"
	string "* = $C000"
	string "START:   "
	string "  \tLDA #$00 ; COMMENT"
	string "\tRTS"
	string ".BYTE 0, 1, 2"
INPUT_END:

TOKENS:
