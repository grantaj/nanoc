CHROUT   = $FFD2

        * = $C000

start:
	;; Demo - dump this entire program
main:
        ;; Push start address (low byte, then high)
        LDA #<start
        PHA
        LDA #>start
        PHA
	
	;; Push end address (low byte, then high)   
        LDA #<end
        PHA
        LDA #>end
        PHA

        ; Call hexdump
        JSR hexdump

	;; restore stack state
	PLA
	PLA
	PLA
	PLA
	
	RTS

	;; ------------------------------------------------------------
	;; Hexdump
	;;
	;; Description:
	;;   Dumps a region of memory in hex format.
	;;
	;; Parameter Passing (stack):
	;;   Caller must push the start and end address (low/high bytes)
	;;   before calling hexdump, in the following order:
	;;       PHA start low
	;;       PHA start high
	;;       PHA end low
	;;       PHA end high
	;;       JSR hexdump
	;;
	;; Caller's responsibility to restore stack state.   
	;;
	
CURRENT  = $FB			; zero-page pointer to current byte
END      = $FD			; zero-page pointer to end of region

hexdump:
	;; parse parameters from the stack
	TSX
	LDA $0106,X		; start low
	STA CURRENT
	LDA $0105,X		; start high
	STA CURRENT+1
	LDA $0104,X             ; end low
	STA END
	LDA $0103,X		;end high
	STA END+1
	
.loop:
	;; Keep going?
	SEC
	LDA END	
	SBC CURRENT
	LDA END+1
	SBC CURRENT+1
	BCC .done

	;; Print address
        LDA CURRENT+1
        JSR printHexByte
        LDA CURRENT
        JSR printHexByte
        LDA #':'
        JSR CHROUT
        LDA #' '
        JSR CHROUT

	;; Print 8 hex bytes
        LDY #0
.hexByteloop:
        LDA (CURRENT),Y
        PHA
        JSR printHexByte
        PLA
        LDA #' '
        JSR CHROUT
        INY
        CPY #8
        BNE .hexByteloop

        ;; Print separator
        LDA #' '
        JSR CHROUT

        ;; Print corresponding 8 ASCII chars
        LDY #0
.asciiByteloop:
        LDA (CURRENT),Y
        CMP #$20
        BCC .notPrintable
        CMP #$7F
        BCS .notPrintable
        JSR CHROUT
        JMP .nextASCII
.notPrintable:
        LDA #'.'
        JSR CHROUT
.nextASCII:
        INY
        CPY #8
        BNE .asciiByteloop

        ;; newline
        LDA #13
        JSR CHROUT

        ;; Increment CURRENT by 8
        CLC
        LDA CURRENT
        ADC #8
        STA CURRENT
        LDA CURRENT+1
        ADC #0
        STA CURRENT+1

        JMP .loop

.done:
        RTS

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
end:	
