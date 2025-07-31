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

;;; test program
	
	lda #<INPUT		; Pointer to input data
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1

	lda #<TOKEN		; Pointer to tokenised output
	sta ZP_PTR0
	lda #>TOKEN
	sta ZP_PTR0+1

	jsr .loop		; tokenise

	;; output tokens
	lda #<TOKEN		; Pointer to tokenised output
	sta ZP_PTR0
	lda #>TOKEN
	sta ZP_PTR0+1

.nextTokenChar:
	lda (ZP_PTR0),Y
	beq .tokenType        	; Null-terminator check
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
	lda #<.tokenStrings
	sta ZP_PTR1
	lda #>.tokenStrings
	sta ZP_PTR1+1
	jsr printString
	lda #$0d
	jsr CHROUT
	jmp .nextTokenChar

.exit:	
	rts

;;; tokeniser starts here

.loop:
	ldy #$0
	lda (ZP_PTR1),y		; End of file marked with NULL
	bne .nextToken

	;; finished - mark end of tokens with $0,$ff
	lda #$00
	sta (ZP_PTR0),y

	inc ZP_PTR0
	bne .writeFF
	inc ZP_PTR0+1
.writeFF:	
	lda #$FF
	sta (ZP_PTR0),y
	
	rts
	
.nextToken:	
	jsr skipWhitespace

	ldy #$0			; skip comments
	lda (ZP_PTR1),y
	cmp #';'
	bne .getTokenValue
	jmp .nextLine

.getTokenValue:
	jsr getLexeme

	;; X = 0: token is special character
	;; X = 1: token is a "SYMBOL"
	


	
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
	include "getLexeme.asm"

;;; Token Strings Array
.tokenStrings:
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
