	;; ------------------------------------------------------------
	;; printHexByte
	;;
	;; Description:
	;;   Prints the 8-bit value in A as two hexadecimal characters
	;;
	;; Calling convention:
	;;   - A register must contain the byte to print (0x00–0xFF)
	;;
	;; Side effects:
	;;   - A is overwritten
	;;   - X and Y preserved
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
	
