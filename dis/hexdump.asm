;;; 6502 hexdump
;;; 
	* = $c000
	;; printHexByte
	;; A = byte to print as hex

main:
	lda #$f9
	jsr printHexByte
	rts
	
printHexByte:
	PHA
	LSR			; obtain the high nibble 
	LSR
	LSR
	LSR         
	JSR .printNibble

	PLA			; obtain low nibble
	AND #$0F      
				; fall through

.printNibble:
	CMP #$0A
	BCC .underTen
	ADC #$06		; carry is set, adding 7
.underTen:
	ADC #$30		; carry is clear
	JSR $FFD2     ; CHROUT
	RTS

	
