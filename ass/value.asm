;;; value.asm
;;;
;;; The assembler's intentionally tiny value grammar:
;;;
;;;     [< | >] atom [ + atom | - atom ]
;;;
;;; atom is $hex, decimal, 'c', or a symbol. There is no precedence, tree,
;;; recursion, or general expression language.

VALUE_OK         = $00
VALUE_UNRESOLVED = $01
VALUE_BAD        = $02

VALUE_PREFIX_NONE = $00
VALUE_PREFIX_LOW  = $01
VALUE_PREFIX_HIGH = $02

;;; parseValue
;;;
;;; Input: ZP_PTR0/X point to the complete value text.
;;; Output: VALUE_* in A, valueResult when resolved.
;;;
;;; X is deliberately not parser state after entry: symbol lookup uses X. The
;;; remaining byte count lives in valueLeft, making that ownership explicit.
;;; ZP_PTR1 is preserved by findSymbol.
parseValue:
	stx valueLeft
	bne .hasValue
	lda #VALUE_BAD
	rts
.hasValue:
	lda #VALUE_PREFIX_NONE
	sta valuePrefix
	lda #$00
	sta valueUnresolved

	ldy #$00
	lda (ZP_PTR0),y
	cmp #'<'
	beq .low
	cmp #'>'
	beq .high
	jmp .first
.low:
	lda #VALUE_PREFIX_LOW
	sta valuePrefix
	jsr advanceValue
	jmp .first
.high:
	lda #VALUE_PREFIX_HIGH
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

	lda valueLeft
	beq .finish
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .plus
	cmp #'-'
	beq .minus
	jmp .bad

.plus:
	jsr advanceValue
	jsr parseValueAtom
	bcc .bad
	lda valueLeft
	bne .bad			; exactly zero or one binary operation
	clc
	lda valueResult
	adc valueAtom
	sta valueResult
	lda valueResult+1
	adc valueAtom+1
	sta valueResult+1
	jmp .finish

.minus:
	jsr advanceValue
	jsr parseValueAtom
	bcc .bad
	lda valueLeft
	bne .bad
	sec
	lda valueResult
	sbc valueAtom
	sta valueResult
	lda valueResult+1
	sbc valueAtom+1
	sta valueResult+1

.finish:
	lda valuePrefix
	beq .status
	cmp #VALUE_PREFIX_LOW
	beq .lowByte
	lda valueResult+1		; >value
	sta valueResult
.lowByte:
	lda #$00			; <value, or clear high byte after >value
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
;;; Consume one atom into valueAtom. An unknown symbol is valid syntax; it marks
;;; the complete value unresolved and contributes zero until the next pass.
parseValueAtom:
	lda valueLeft
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
	bcc .symbol
	cmp #'9'+1
	bcc .decimal
.symbol:
	jmp parseSymbolAtom
.decimal:
	jmp parseDecimalAtom
.bad:
	clc
	rts

;;; parseHexAtom
;;; $ followed by 1..4 hexadecimal digits. Both cases are accepted because the
;;; existing nanoc source uses lowercase constants such as $fc.
parseHexAtom:
	lda #$00
	sta valueAtom
	sta valueAtom+1
	ldx #$00			; digit count is local to this routine
	jsr advanceValue		; '$'
.loop:
	lda valueLeft
	beq .done
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .done
	cmp #'-'
	beq .done
	jsr valueHexNibble
	bcc .bad
	tay				; nibble is local scratch
	inx
	cpx #$05
	bcs .bad
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	asl valueAtom
	rol valueAtom+1
	tya
	ora valueAtom
	sta valueAtom
	jsr advanceValue
	jmp .loop
.done:
	cpx #$00
	beq .bad
	sec
	rts
.bad:
	clc
	rts

;;; A = ASCII hex digit. Return nibble in A/carry set.
valueHexNibble:
	cmp #'0'
	bcc .bad
	cmp #'9'+1
	bcc .decimal
	and #$df			; fold a..f to A..F
	cmp #'A'
	bcc .bad
	cmp #'F'+1
	bcs .bad
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

;;; parseDecimalAtom
;;; Decimal arithmetic is naturally modulo 16 bits, like the machine itself.
parseDecimalAtom:
	lda #$00
	sta valueAtom
	sta valueAtom+1
.loop:
	lda valueLeft
	beq .done
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .done
	cmp #'-'
	beq .done
	cmp #'0'
	bcc .bad
	cmp #'9'+1
	bcs .bad
	sec
	sbc #'0'
	tax				; current digit is local scratch

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

	txa
	clc
	adc valueAtom
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

;;; parseCharAtom
;;; A character atom is exactly an opening quote, one byte, and a closing quote.
parseCharAtom:
	lda valueLeft
	cmp #$03
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

;;; parseSymbolAtom
;;; Keep the name as a view into the value text, then ask the linear table.
parseSymbolAtom:
	lda ZP_PTR0
	sta symbolName
	lda ZP_PTR0+1
	sta symbolName+1
	lda #$00
	sta symbolNameLength
.loop:
	lda valueLeft
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

	;; findSymbol borrows ZP_PTR0, so preserve our value cursor explicitly.
	lda ZP_PTR0
	pha
	lda ZP_PTR0+1
	pha
	jsr findSymbol
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0
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
;;; Move the value cursor one byte. X is intentionally not involved.
advanceValue:
	inc ZP_PTR0
	bne .noCarry
	inc ZP_PTR0+1
.noCarry:
	dec valueLeft
	rts

valueResult:		word 0

;;; Small explicit parser state.
valueLeft:		byte 0
valuePrefix:		byte 0
valueUnresolved:	byte 0
valueAtom:		word 0
valueTemp:		word 0
