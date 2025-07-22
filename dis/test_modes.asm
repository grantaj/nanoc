;;; Unit test for addressing modes
	
CHROUT = $FFD2	
p = $FC				; pointer to current byte for dissasembly
	
	* = $c000
	
main:

	lda #<data		; initialise pointer
	sta p
	lda #>data
	sta p+1

	jsr printLDA
	jsr immediate
	jsr printCR

	jsr printLDA
	jsr absolute
	jsr printCR

	jsr printLDA
	jsr zeroPage
	jsr printCR

	jsr printLDA
	jsr indexedZeroPageX
	jsr printCR

	jsr printLDA
	jsr indexedZeroPageY
	jsr printCR

	jsr printLDA
	jsr indexedAbsoluteX
	jsr printCR

	jsr printLDA
	jsr indexedAbsoluteY
	jsr printCR

	jsr printLDA
	jsr indexedIndirectX
	jsr printCR

	jsr printLDA
	jsr indexedIndirectY
	jsr printCR

	jsr printLDA
	jsr absoluteIndirect
	jsr printCR

	jsr printBCC
	jsr relative
	jsr printCR

	rts
	
printLDA:	
	lda #'L'
	jsr CHROUT
	lda #'D'
	jsr CHROUT
	lda #'A'
	jsr CHROUT
	lda #' '
	jsr CHROUT
	rts

printBCC:	
	lda #'B'
	jsr CHROUT
	lda #'C'
	jsr CHROUT
	jsr CHROUT
	lda #' '
	jsr CHROUT
	rts
	
printCR:
	lda #$0D
	jsr CHROUT
	rts

	* = $c100
data:
	byte $fd, $12

	include "modes.asm"	
