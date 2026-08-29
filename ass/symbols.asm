;;; symbols.asm
;;;
;;; Small linear symbol table for the native two-pass assembler.
;;; Names stay in the source buffer; an entry is only pointer, length, value,
;;; and one local-label scope byte.

SYMBOL_NAME_LO  = 0
SYMBOL_NAME_HI  = 1
SYMBOL_LENGTH   = 2
SYMBOL_VALUE_LO = 3
SYMBOL_VALUE_HI = 4
SYMBOL_SCOPE    = 5
SYMBOL_SIZE     = 6

SYMBOL_OK        = $00
SYMBOL_DUPLICATE = $01
SYMBOL_FULL      = $02
SYMBOL_NO_SCOPE  = $03

VALUE_OK         = $00
VALUE_UNRESOLVED = $01
VALUE_BAD        = $02

;;; resetSymbols
;;; Empty the caller-owned table. A is clobbered.
resetSymbols:
	lda symbolTableStart
	sta symbolTableEnd
	lda symbolTableStart+1
	sta symbolTableEnd+1
	rts

;;; defineSymbol
;;;
;;; symbolName/symbolNameLength identify source text; symbolValue is the value.
;;; Returns SYMBOL_* in A. ZP_PTR1 is preserved.
defineSymbol:
	jsr findSymbol
	bcc .new
	lda #SYMBOL_DUPLICATE
	rts
.new:
	jsr symbolScope
	bcs .scopeReady
	lda #SYMBOL_NO_SCOPE
	rts
.scopeReady:
	sta symbolWantedScope

	clc
	lda symbolTableEnd
	adc #SYMBOL_SIZE
	sta symbolNext
	lda symbolTableEnd+1
	adc #$00
	sta symbolNext+1
	lda symbolNext+1
	cmp symbolTableLimit+1
	bcc .room
	bne .full
	lda symbolNext
	cmp symbolTableLimit
	bcc .room
	beq .room
.full:
	lda #SYMBOL_FULL
	rts

.room:
	lda symbolTableEnd
	sta ZP_PTR0
	lda symbolTableEnd+1
	sta ZP_PTR0+1
	ldy #SYMBOL_NAME_LO
	lda symbolName
	sta (ZP_PTR0),y
	iny
	lda symbolName+1
	sta (ZP_PTR0),y
	iny
	lda symbolNameLength
	sta (ZP_PTR0),y
	iny
	lda symbolValue
	sta (ZP_PTR0),y
	iny
	lda symbolValue+1
	sta (ZP_PTR0),y
	iny
	lda symbolWantedScope
	sta (ZP_PTR0),y

	lda symbolNext
	sta symbolTableEnd
	lda symbolNext+1
	sta symbolTableEnd+1
	lda #SYMBOL_OK
	rts

;;; findSymbol
;;;
;;; Look up symbolName/symbolNameLength. Global names use scope zero; `.name`
;;; uses currentScope. Returns symbolValue and carry set, or carry clear.
;;; ZP_PTR0 and ZP_PTR1 are preserved; A, X, Y and flags are clobbered.
findSymbol:
	lda ZP_PTR0
	sta savedZp0
	lda ZP_PTR0+1
	sta savedZp0+1
	lda ZP_PTR1
	sta savedZp1
	lda ZP_PTR1+1
	sta savedZp1+1

	jsr symbolScope
	bcs .scopeReady
	jmp .notFound
.scopeReady:
	sta symbolWantedScope
	lda symbolTableStart
	sta symbolScan
	lda symbolTableStart+1
	sta symbolScan+1

.next:
	lda symbolScan
	cmp symbolTableEnd
	bne .entry
	lda symbolScan+1
	cmp symbolTableEnd+1
	bne .entry
	jmp .notFound
.entry:
	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_LENGTH
	lda (ZP_PTR0),y
	cmp symbolNameLength
	beq .lengthOk
	jmp .advance
.lengthOk:
	ldy #SYMBOL_SCOPE
	lda (ZP_PTR0),y
	cmp symbolWantedScope
	beq .scopeOk
	jmp .advance
.scopeOk:

	ldy #SYMBOL_NAME_LO
	lda (ZP_PTR0),y
	sta storedSymbolName
	iny
	lda (ZP_PTR0),y
	sta storedSymbolName+1
	lda storedSymbolName
	sta ZP_PTR0
	lda storedSymbolName+1
	sta ZP_PTR0+1
	lda symbolName
	sta ZP_PTR1
	lda symbolName+1
	sta ZP_PTR1+1
	ldy #$00
.compare:
	lda (ZP_PTR0),y
	cmp (ZP_PTR1),y
	bne .advance
	iny
	cpy symbolNameLength
	bne .compare

	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_VALUE_LO
	lda (ZP_PTR0),y
	sta symbolValue
	iny
	lda (ZP_PTR0),y
	sta symbolValue+1
	sec
	jmp .restore

.advance:
	clc
	lda symbolScan
	adc #SYMBOL_SIZE
	sta symbolScan
	bcc .noPage
	inc symbolScan+1
.noPage:
	jmp .next
.notFound:
	clc
.restore:
	lda savedZp0
	sta ZP_PTR0
	lda savedZp0+1
	sta ZP_PTR0+1
	lda savedZp1
	sta ZP_PTR1
	lda savedZp1+1
	sta ZP_PTR1+1
	rts

;;; symbolScope
;;; Return this name's scope in A/carry set. A local name before any global
;;; label is invalid and returns carry clear.
symbolScope:
	lda symbolNameLength
	beq .bad
	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'.'
	beq .local
	lda #$00
	sec
	rts
.local:
	lda currentScope
	beq .bad
	sec
	rts
.bad:
	clc
	rts

;;; parseValue
;;;
;;; ZP_PTR0/X identify:
;;;
;;;     [< | >] atom [ + atom | - atom ]
;;;
;;; atom is $hex, decimal, 'c', or a symbol. Arithmetic is 16-bit. There is no
;;; precedence, parentheses, recursion, or other expression machinery.
;;;
;;; Returns VALUE_* in A and valueResult on success. ZP_PTR1 is preserved;
;;; ZP_PTR0/X are consumed while reading the value.
parseValue:
	cpx #$00
	bne .hasValue
	lda #VALUE_BAD
	rts
.hasValue:
	lda #$00
	sta valuePrefix
	sta valueUnresolved
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'<'
	beq .low
	cmp #'>'
	beq .high
	jmp .first
.low:
	lda #$01
	sta valuePrefix
	jsr advanceValue
	jmp .first
.high:
	lda #$02
	sta valuePrefix
	jsr advanceValue
.first:
	jsr parseValueAtom
	bcs .firstOk
	jmp .bad
.firstOk:
	lda valueAtom
	sta valueResult
	lda valueAtom+1
	sta valueResult+1
	cpx #$00
	bne .operator
	jmp .finish
.operator:
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .plus
	cmp #'-'
	beq .minus
	jmp .bad
.plus:
	lda #$01
	sta valueOperator
	jsr advanceValue
	jmp .second
.minus:
	lda #$02
	sta valueOperator
	jsr advanceValue
.second:
	jsr parseValueAtom
	bcs .secondOk
	jmp .bad
.secondOk:
	cpx #$00
	beq .secondDone
	jmp .bad			; at most one binary operation
.secondDone:
	lda valueOperator
	cmp #$01
	beq .add
	sec
	lda valueResult
	sbc valueAtom
	sta valueResult
	lda valueResult+1
	sbc valueAtom+1
	sta valueResult+1
	jmp .finish
.add:
	clc
	lda valueResult
	adc valueAtom
	sta valueResult
	lda valueResult+1
	adc valueAtom+1
	sta valueResult+1
.finish:
	lda valuePrefix
	beq .status
	cmp #$01
	beq .lowByte
	lda valueResult+1
	sta valueResult
.lowByte:
	lda #$00
	sta valueResult+1
.status:
	lda valueUnresolved
	beq .ok
	lda #VALUE_UNRESOLVED
	rts
.ok:
	lda #VALUE_OK
	rts
.bad:
	lda #VALUE_BAD
	rts

;;; parseValueAtom
;;; Consume one atom into valueAtom. Missing symbols are valid syntax and mark
;;; the complete value unresolved.
parseValueAtom:
	cpx #$00
	beq .bad
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'$'
	bne .notHex
	jmp parseHexAtom
.notHex:
	cmp #39				; apostrophe
	bne .notChar
	jmp parseCharAtom
.notChar:
	cmp #'0'
	bcs .maybeDecimal
	jmp parseSymbolAtom
.maybeDecimal:
	cmp #'9'+1
	bcs .symbol
	jmp parseDecimalAtom
.symbol:
	jmp parseSymbolAtom
.bad:
	clc
	rts

parseHexAtom:
	lda #$00
	sta valueAtom
	sta valueAtom+1
	sta valueDigits
	jsr advanceValue		; '$'
.loop:
	cpx #$00
	beq .done
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .done
	cmp #'-'
	beq .done
	jsr valueHexNibble
	bcc .bad
	pha
	inc valueDigits
	lda valueDigits
	cmp #$05
	bcs .badPop
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	pla
	ora valueAtom
	sta valueAtom
	jsr advanceValue
	jmp .loop
.done:
	lda valueDigits
	beq .bad
	sec
	rts
.badPop:
	pla
.bad:
	clc
	rts

valueHexNibble:
	cmp #'0'
	bcc .bad
	cmp #'9'+1
	bcc .decimal
	cmp #'A'
	bcc .lower
	cmp #'F'+1
	bcc .upper
.lower:
	cmp #'a'
	bcc .bad
	cmp #'f'+1
	bcs .bad
	sec
	sbc #'a'-10
	sec
	rts
.upper:
	sec
	sbc #'A'-10
	sec
	rts
.decimal:
	sec
	sbc #'0'
	sec
	rts
.bad:
	clc
	rts

parseDecimalAtom:
	lda #$00
	sta valueAtom
	sta valueAtom+1
.loop:
	cpx #$00
	bne .haveByte
	jmp .done
.haveByte:
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	bne .notPlus
	jmp .done
.notPlus:
	cmp #'-'
	bne .notMinus
	jmp .done
.notMinus:
	cmp #'0'
	bcs .atLeastZero
	jmp .bad
.atLeastZero:
	cmp #'9'+1
	bcc .digit
	jmp .bad
.digit:
	sec
	sbc #'0'
	sta valueDigit

	;; value = value*10 + digit, naturally modulo 16 bits.
	lda valueAtom
	sta valueTemp
	lda valueAtom+1
	sta valueTemp+1
	asl valueAtom
	rol valueAtom+1			; *2
	asl valueTemp
	rol valueTemp+1
	asl valueTemp
	rol valueTemp+1
	asl valueTemp
	rol valueTemp+1			; *8
	clc
	lda valueAtom
	adc valueTemp
	sta valueAtom
	lda valueAtom+1
	adc valueTemp+1
	sta valueAtom+1
	clc
	lda valueAtom
	adc valueDigit
	sta valueAtom
	bcc .next
	inc valueAtom+1
.next:
	jsr advanceValue
	jmp .loop
.done:
	sec
	rts
.bad:
	clc
	rts

parseCharAtom:
	cpx #$03
	bcc .bad
	jsr advanceValue		; opening quote
	ldy #$00
	lda (ZP_PTR0),y
	sta valueAtom
	lda #$00
	sta valueAtom+1
	jsr advanceValue
	ldy #$00
	lda (ZP_PTR0),y
	cmp #39
	bne .bad
	jsr advanceValue		; closing quote
	sec
	rts
.bad:
	clc
	rts

parseSymbolAtom:
	lda ZP_PTR0
	sta symbolName
	lda ZP_PTR0+1
	sta symbolName+1
	lda #$00
	sta symbolNameLength
.loop:
	cpx #$00
	beq .lookup
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .lookup
	cmp #'-'
	beq .lookup
	inc symbolNameLength
	jsr advanceValue
	jmp .loop
.lookup:
	lda symbolNameLength
	beq .bad
	jsr findSymbol
	bcc .unresolved
	lda symbolValue
	sta valueAtom
	lda symbolValue+1
	sta valueAtom+1
	sec
	rts
.unresolved:
	lda #$01
	sta valueUnresolved
	lda #$00
	sta valueAtom
	sta valueAtom+1
	sec
	rts
.bad:
	clc
	rts

;;; advanceValue
;;; Move the value pointer one byte and reduce X. A and Y are preserved.
advanceValue:
	inc ZP_PTR0
	bne .noCarry
	inc ZP_PTR0+1
.noCarry:
	dex
	rts

;;; Caller-owned symbol-table region and current local-label scope.
symbolTableStart:	word 0
symbolTableEnd:		word 0
symbolTableLimit:	word 0
currentScope:		byte 0

;;; Public query/result state.
symbolName:		word 0
symbolNameLength:	byte 0
symbolValue:		word 0
valueResult:		word 0

;;; Scratch.
symbolWantedScope:	byte 0
symbolNext:		word 0
symbolScan:		word 0
storedSymbolName:	word 0
savedZp0:		word 0
savedZp1:		word 0
valuePrefix:		byte 0
valueOperator:		byte 0
valueUnresolved:	byte 0
valueAtom:		word 0
valueDigits:		byte 0
valueDigit:		byte 0
valueTemp:		word 0
