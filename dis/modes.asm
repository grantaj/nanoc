;;; modes.asm
;;; Output formatter for 6502 addressing modes
;;;
;;; First bye of instruction is opcode
;;; It is assumed that this, as well as the separating space
;;; have been output already
;;; Second byte of the instruction is pointed to by
;;; p (low) / p+1 (high)
;;; All these routines use A and preserve X, Y
	
CHROUT = $FFD2
	p = $FC			; pointer to current byte for dissasembly
	
	* = $c000

main:
	;; Unit test for addressing modes
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

;;; ----------------------------------------------------------------------
	
accumulator:
	;; Operation on the accumulator
	;; No operand, nothing to output
	rts
	
immediate:
	;; Operand contained in the second byte of the instruction
	tya
	pha
	lda #'#'
	jsr CHROUT
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),y
	jsr printHexByte
	pla
	tay
	rts
	
absolute:
	;; Second btye of instruction specifies the low byte
	;; of the effective address, third byte specifies high byte
	tya			; don't clobber Y
	pha
	lda #'$'
	jsr CHROUT
	ldy #$01
	lda (p),y
	jsr printHexByte
	dey
	lda (p),y
	jsr printHexByte
	pla			; restore Y
	tay
	rts

zeroPage:
	;; Second byte of instruction specifies zero page address
	tya
	pha
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),y
	jsr printHexByte
	pla
	tay
	rts
	
indexedZeroPageX:
	;; Second byte is added to X with no carry
	;; The result is the zero page address
	tya
	pha
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),y
	jsr printHexByte
	jsr commaX
	pla
	tay
	rts
	
indexedZeroPageY:	
	;; Second byte is added to Y with no carry
	;; forming effective zero page address
	tya
	pha
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),Y
	jsr printHexByte
	jsr commaY
	pla
	tay
	rts
	
indexedAbsoluteX:
	;; Second and third bytes are L/H of address
	;; X is added to L with carry to H forming effective address
	jsr absolute
	jsr commaX
	rts
	
indexedAbsoluteY:	
	;; Second and third bytes are L/H of address
	;; Y is added to L with carry to H forming effective address
	jsr absolute
	jsr commaY
	rts
	
implied:
	;; No operand, nothing to output
	rts

relative:
	;; Second byte is signed offset
	;; Branch will be to address of next instruction + offset
	;; I.e. address of second byte + 1 + offset
	tya
	pha
	lda #'$'
	jsr CHROUT
	lda p			; low byte
	ldy #$0
	clc
	adc (p),y		; + signed offset
	adc #$01		; + 1
	pha			; store result
	lda (p),y		; reload offset
	bmi .negative		; check if sign bit set
.positive:			; offset was positive
	lda p+1			; high byte
	adc #$0			; add the carry bit
	jmp .output
	.negative:
	lda p+1			; offset was negative
	adc #$ff		; add carry and sign extension
.output:	
	jsr printHexByte
	pla
	jsr printHexByte
	pla
	tay
	rts

indexedIndirectX:
	;; second byte of instruction is added to X discarding carry
	;; result is a zero page address z whose contents are the low
	;; byte of the effective address a, and z+1 stores
	;; high byte of the effective address
	tya
	pha
	lda #'('
	jsr CHROUT
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),y
	jsr printHexByte
	jsr commaX
	lda #')'
	jsr CHROUT
	pla
	tay
	rts

indexedIndirectY:
	;; second byte of instruction points to a zero page address z
	;; contents of z are added to Y with carry. This is the low byte
	;; of the effective address. The high byte is the contents of z+1
	;; with the carry added
	tya
	pha
	lda #'('
	jsr CHROUT
	lda #'$'
	jsr CHROUT
	ldy #$0
	lda (p),Y
	jsr printHexByte
	lda #')'
	jsr CHROUT
	jsr commaY
	pla
	tay
	rts

absoluteIndirect:
	;; second and third byte are low and high byte form a pointer
	;; to the effective address
	lda #'('
	jsr CHROUT
	jsr absolute
	lda #')'
	jsr CHROUT
	rts

;;; helpers

commaX:
	lda #','
	jsr CHROUT
	lda #'X'
	jsr CHROUT
	rts
	
commaY:
	lda #','
	jsr CHROUT
	lda #'Y'
	jsr CHROUT
	rts
	
printHexByte:
        PHA
        LSR
        LSR
        LSR
        LSR
        JSR .printNibble
        PLA
        AND #$0F
.printNibble:
        CMP #$0A
        BCC .underTen
        ADC #$06      ; assumes carry set
.underTen:
        ADC #$30
        JSR CHROUT
        RTS
