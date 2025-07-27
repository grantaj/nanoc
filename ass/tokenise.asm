	include "zp.inc"
	CHROUT = $ffd2
	
;;; Token types
	
	LABEL = 1
	SYMBOL = 2
	DIRECTIVE = 3
	MNEMONIC = 4
	OPERAND = 5
	EQUALS = 6


	* = $c000

	lda #<INPUT		; Pointer to input data
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1

	lda #<TOKEN		; Pointer to tokenised output
	sta ZP_PTR0
	lda #>TOKEN
	sta ZP_PTR0+1

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
	bne .getTokenValue
	jmp .nextLine

.getTokenValue:
	tax			; X holds first character
	jsr getLexeme

	;; Token classification
	;;   X = first character
	;;   A = last character
.checkLabel:
	cpx #':'
	bne .checkDirective
	lda #DIRECTIVE
	sta (ZP_PTR0),y
	jmp .nextToken
	
.checkDirective:
	;; starts with a dot?
	cmp #'.'
	bne .checkEquals
	lda #DIRECTIVE
	sta (ZP_PTR0),y
	jmp .nextToken

.checkEquals:
	;; ends with equals?
	cpx #'='
	bne .mnemonicOrOperand
	lda #EQUALS
	sta (ZP_PTR0),y
	;; previous token is a SYMBOL
	;; TODO need to add check to make sure there was a previous token
	lda prevTokenValid
	beq .checkEqualsDone
	
	lda #SYMBOL
	sta (prevTokenType)

.chackEqualsDone:
	jmp .nextToken
	
.mnemonicOrOperand:
	lda (prevTokenType)
	cmp #MNEMONIC
	bne .operand
	lda #MNEMONIC
	sta (ZP_PTR0),y
	jmp .nextToken
	
.operand:
	lda #OPERAND
	sta (ZP_PTR0),y
	jmp .nextToken

	
.nextToken:
	lda ZP_PTR0
	sta prevTokenType
	lda ZP_PTR0+1
	sta prevTokenType+1
	lda #$01
	sta prevTokenValid
	
	inc ZP_PTR0
	bne .jmploop
	inc ZP_PTR0+1
.jmploop:
	jmp .loop
	
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
	string "  	LDA #$00 ; COMMENT"
	string "	RTS"
	string ".BYTE 0, 1, 2"
	byte 0			; end of file

prevTokenType:			; pointer to previous token TYPE 
	byte 0, 0

prevTokenValid:
	byte 0			; 1 if there is a previous token 
	
TOKENS:	
