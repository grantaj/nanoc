	include "zp.inc"
	CHROUT = $ffd2
	
;;; Token types
	

	* = $c000

;;; test program
	
	lda #<INPUT		; Pointer to input data
	sta ZP_PTR1
	lda #>INPUT
	sta ZP_PTR1+1

	lda #<TOKENS		; Pointer to tokenised output
	sta ZP_PTR0
	lda #>TOKENS
	sta ZP_PTR0+1

	jsr .loop		; tokenise

	
	lda #<TOKENS 		; Rewind to start of output tokens
	sta ZP_PTR0
	lda #>TOKENS
	sta ZP_PTR0+1

.nextTokenChar:
	lda (ZP_PTR0),Y
	beq .tokenDone        	; Null-terminator check
	jsr CHROUT
	inc ZP_PTR0
	bne .nextTokenChar	
	inc ZP_PTR0+1     	
	jmp .nextTokenChar

.tokenDone:
	inc ZP_PTR0
	bne .printCR		
	inc ZP_PTR0+1     	
.printCR:
	lda #$0d
	jsr CHROUT

	lda (ZP_PTR0),y
	cmp #$FF
	bne .keepGoing
	jmp .exit
	
.keepGoing:	
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

;;; X contains token type
;;; null terminated token value has been stored at ZP_PTR0


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

;;; A made up program to test tokenisation
INPUT:
	string "SYMBOL"
	string "     		; COMMENT"
	string "* = $C000"
	string "START:   "
	string "  	LDA #$00 ; COMMENT"
	string "	RTS"
	string ".BYTE 0, 1, 2"
	byte 0			; end of file
	
TOKENS:	
