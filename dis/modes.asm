;;; modes.asm
;;; Output formatter for 6502 addressing modes
;;;
;;; First bye of instruction is opcode
;;; It is assumed that this, as well as the separating space
;;; have been output already
;;; Second byte of the instruction is pointed to by
;;; zero page pointer p (low) / p+1 (high)
;;; All routines preserve X, Y
;;; All routines set A to the opcode width
;;;
;;; Mode indexes refer to addressing mode indexes in opcode_table.asm
;;; ----------------------------------------------------------------------

	;; Jump table
address_mode_table:	
	word implied
	word accumulator
	word immediate
	word zeroPage
	word indexedZeroPageX
	word indexedZeroPageY
	word absolute
	word indexedAbsoluteX
	word indexedAbsoluteY
	word absoluteIndirect
	word indexedIndirectX
	word indexedIndirectY
	word relative
	word undocumented
	
	
implied:
	;; Mode 0
	;; No operand nothing to output
	lda #$0
	rts
	
accumulator:
	;; Mode 1
	;; Operation on the accumulator
	;; No operand, nothing to output
	lda #$0
	rts
	
immediate:
	;; Mode 2
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
	lda #$1
	rts
	
zeroPage:
	;; Mode 3
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
	lda #$1
	rts
	
indexedZeroPageX:
	;; Mode 4
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
	lda #$1
	rts
	
indexedZeroPageY:
	;; Mode 5
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
	lda #$1
	rts

absolute:
	;; Mode 6
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
	lda #$2
	rts
	
indexedAbsoluteX:
	;; Mode 7
	;; Second and third bytes are L/H of address
	;; X is added to L with carry to H forming effective address
	jsr absolute
	jsr commaX
	lda #$2
	rts
	
indexedAbsoluteY:
	;; Mode 8
	;; Second and third bytes are L/H of address
	;; Y is added to L with carry to H forming effective address
	jsr absolute
	jsr commaY
	lda #$2
	rts
	
absoluteIndirect:
	;; Mode 9
	;; second and third byte are low and high byte form a pointer
	;; to the effective address
	lda #'('
	jsr CHROUT
	jsr absolute
	lda #')'
	jsr CHROUT
	lda #$2
	rts

indexedIndirectX:
	;; Mode A
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
	lda #$1
	rts

indexedIndirectY:
	;; Mode B
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
	lda #$1
	rts


relative:
	;; Mode C
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
	lda #$1
	rts

undocumented:
	;; for undocumented opcodes
	lda #$0
	rts
	
;;; ----------------------------------------------------------------------
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
