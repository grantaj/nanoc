;;; 6502 Disassembler
;;; Alex Grant
	
CHROUT = $FFD2	
p = $FC				; start of region
q = $FE				; end of region
	
	* = $c000
	
main:
	;; Initialisation -----------------------------------------------------
	
	lda #<main		; initialise current byte pointer
	sta p
	lda #>main
	sta p+1

	lda #<end
	sta q
	lda #>end
	sta q+1

	;; Print address
	lda #'$'
	jsr CHROUT
	lda q+1
	jsr printHexByte
	lda q
	jsr printHexByte
	jsr printCR
	
.loop:
	;; Main Loop ----------------------------------------------------------

	;; Print address
	lda #'$'
	jsr CHROUT
	lda p+1
	jsr printHexByte
	lda p
	jsr printHexByte
	lda #' '
	jsr CHROUT
	
	;; Get opcode
	ldy #$0			; q = q + opcode*2
	lda (p),y		; opcode

	;; Opcode table lookup ------------------------------------------------
	;; 
	;; opcode_table has one two-byte entry for every possible
	;; opcode in the range 00..FF including undocumented opcodes
	;; The entry we want is as opcode_table + 2X where X is the opcode.
	;; Opcodes in the range 00..7F result in indexes in
	;; the range 00..FF, on the first page of the table.
	;; Opcodes inthe range 80..FF result in indexes in
	;; the range 100..1FF, on the second page
	
	bmi .secondPage

	;; opcode is in the range 00..7F
	;; lookup from first page of opcode table
	asl
	tax
	lda opcode_table,x	; mnemonic index
	inx
	ldy opcode_table,x	; addressing mode
	jmp .outputOpcode
	
.secondPage:
	;; opcode is in the range 80..FF
	;; lookup from second page of opcode table
	asl
	tax
	lda opcode_table+$100,x	; mnemonic index
	inx
	ldy opcode_table+$100,x	; addressing mode

	;; output mnemonic ----------------------------------------------------
	
.outputOpcode:
	;; A = mnemonic index
	;; Y = addressing mode

	sta temp		; multiply mnemonic index by 3
	asl
	clc			
	adc temp	
	tax			; index of first character

	adc #$3			; index of next mnemonic in table
	sta temp
	
.nextChar:	
	lda mnemonic_table,x
	jsr CHROUT
	inx
	cpx temp
	bne .nextChar
	lda #$' '
	jsr CHROUT

	;; output formatted operand -------------------------------------------

	clc
	lda #$1			;increment pointer
	adc p
	sta p
	lda #$0
	adc p+1
	sta p+1
	
	tya 			; address mode index
	asl			; indexing words
	tay
	lda address_mode_table,y ; copy address of mode formatter 
	sta jumpVector		 ; to jump vector
	iny
	lda address_mode_table,y
	sta jumpVector+1
	
	lda #>.continue - 1	; push return address onto stack
	pha			; so that jump looks like jsr
	lda #<.continue - 1	; jsr pulls low byte then high byte
	pha			; so we need to push high then low

	jmp (jumpVector)

.continue:
	
	;; on return, A contains operand width
	clc			; increment pointer	
	adc p
	sta p
	lda #$0
	adc p+1
	sta p+1
	
.end_of_line:	
	
	lda #$0D
	jsr CHROUT

	;; lda count
	;; adc #$1
	;; sta count
	;; cmp #$c
	;; beq .done

	;; jmp .loop

	;; rts
	
	;; stop?
	clc
	lda p
	sbc q
	lda p+1
	sbc q+1
	bcs .done
	jmp .loop

	
.done:
end:	
	rts


jumpVector:
	word implied

temp:
	byte 0
count:
	byte 0
	
printCR:
	lda #$0d
	jsr CHROUT
	rts

	include "modes.asm"		
	include "opcode_table.asm"
	include "mnemonic_table.asm"

