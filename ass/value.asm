;;; value.asm
;;;
;;; The assembler has one deliberately tiny value grammar:
;;;
;;;     [< | >] atom [ + atom | - atom ]
;;;
;;; atom is $hex, decimal, 'c', a constant, or a label. There is no precedence,
;;; tree, recursion, or general expression language.
;;;
;;; Parsing produces either a fixed 16-bit value or the one forward-reference
;;; recipe needed after a source line disappears:
;;;
;;;     undefined label entry + 16-bit addend + optional < / > prefix
;;;
;;; A label becomes an ordinary fixed value as soon as its definition is seen.

VALUE_OK          = $00
VALUE_UNRESOLVED  = $01
VALUE_BAD         = $02
VALUE_SYMBOL_FULL = $03
VALUE_SCOPE_ERROR = $04

VALUE_PREFIX_NONE = $00
VALUE_PREFIX_LOW  = $01
VALUE_PREFIX_HIGH = $02

VALUE_ATOM_FIXED = $00
VALUE_ATOM_LABEL = $01

;;; parseValue
;;;
;;; Input: ZP_PTR0/X = complete value text.
;;; Output:
;;;   VALUE_OK         -> valueResult is fixed
;;;   VALUE_UNRESOLVED -> captured* describes one undefined-label value
;;;   VALUE_BAD / VALUE_SYMBOL_FULL / VALUE_SCOPE_ERROR
;;;
;;; X is deliberately not parser state after entry; the remaining byte count
;;; lives in valueLeft because symbol lookup uses X.
parseValue:
	stx valueLeft
	bne .hasValue
	lda #VALUE_BAD
	rts
.hasValue:
	lda #$00
	sta capturedHasSymbol
	sta capturedSymbol
	sta capturedSymbol+1
	sta capturedAddend
	sta capturedAddend+1
	lda #VALUE_PREFIX_NONE
	sta capturedPrefix

	ldy #$00
	lda (ZP_PTR0),y
	cmp #'<'
	beq .low
	cmp #'>'
	beq .high
	jmp .first
.low:
	lda #VALUE_PREFIX_LOW
	sta capturedPrefix
	jsr advanceValue
	jmp .first
.high:
	lda #VALUE_PREFIX_HIGH
	sta capturedPrefix
	jsr advanceValue

.first:
	jsr parseValueAtom
	bcs .firstAtomOk
	jmp .atomError
.firstAtomOk:
	lda valueAtomKind
	cmp #VALUE_ATOM_LABEL
	beq .firstLabel
	lda valueAtom
	sta capturedAddend
	lda valueAtom+1
	sta capturedAddend+1
	jmp .operator
.firstLabel:
	lda #$01
	sta capturedHasSymbol
	lda valueAtomSymbol
	sta capturedSymbol
	lda valueAtomSymbol+1
	sta capturedSymbol+1

.operator:
	lda valueLeft
	bne .hasOperator
	jmp .finish
.hasOperator:
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'+'
	beq .haveOperator
	cmp #'-'
	beq .haveOperator
	jmp .bad
.haveOperator:
	sta valueOperator
	jsr advanceValue
	jsr parseValueAtom
	bcs .secondAtomOk
	jmp .atomError
.secondAtomOk:
	lda valueLeft
	beq .operatorDone
	jmp .bad			; exactly zero or one binary operation
.operatorDone:
	lda valueAtomKind
	cmp #VALUE_ATOM_LABEL
	beq .secondLabel

	;; A fixed second atom is either ordinary 16-bit arithmetic or the addend
	;; attached to an unresolved label.
	lda valueOperator
	cmp #'+'
	beq .addFixed
	sec
	lda capturedAddend
	sbc valueAtom
	sta capturedAddend
	lda capturedAddend+1
	sbc valueAtom+1
	sta capturedAddend+1
	jmp .finish
.addFixed:
	clc
	lda capturedAddend
	adc valueAtom
	sta capturedAddend
	lda capturedAddend+1
	adc valueAtom+1
	sta capturedAddend+1
	jmp .finish

.secondLabel:
	lda capturedHasSymbol
	bne .bad			; no label +/- label machinery
	lda valueOperator
	cmp #'+'
	bne .bad			; literal - label is deliberately unsupported
	lda #$01
	sta capturedHasSymbol
	lda valueAtomSymbol
	sta capturedSymbol
	lda valueAtomSymbol+1
	sta capturedSymbol+1

.finish:
	lda capturedHasSymbol
	bne .deferred
	lda capturedAddend
	sta valueResult
	lda capturedAddend+1
	sta valueResult+1
	jsr applyValuePrefix
	lda #VALUE_OK
	rts

.deferred:
	lda #VALUE_UNRESOLVED
	rts

.atomError:
	lda valueStatus
	rts
.bad:
	lda #VALUE_BAD
	rts

;;; parseValueAtom
;;; Consume one atom. Fixed atoms use valueAtom; unresolved labels use
;;; valueAtomSymbol. Carry clear returns valueStatus.
parseValueAtom:
	lda valueLeft
	beq .bad
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'$'
	bne .notHex
	jsr parseHexAtom
	bcc .bad
	jmp .fixed
.notHex:
	cmp #39				; apostrophe
	bne .notChar
	jsr parseCharAtom
	bcc .bad
	jmp .fixed
.notChar:
	cmp #'0'
	bcc .symbol
	cmp #'9'+1
	bcc .decimal
.symbol:
	jmp parseValueSymbolAtom
.decimal:
	jsr parseDecimalAtom
	bcc .bad
.fixed:
	lda #VALUE_ATOM_FIXED
	sta valueAtomKind
	sec
	rts
.bad:
	lda #VALUE_BAD
	sta valueStatus
	clc
	rts

;;; parseHexAtom
;;; $ followed by 1..4 hexadecimal digits. Both cases are accepted because ass
;;; source uses lower-case hex as ordinary 6502 source does.
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

;;; parseValueSymbolAtom
;;; Constants and already-defined labels are fixed values. Only a label whose
;;; definition has not yet appeared remains unresolved and is represented by its
;;; symbol-table entry.
parseValueSymbolAtom:
	lda ZP_PTR0
	sta symbolName
	lda ZP_PTR0+1
	sta symbolName+1
	lda #$00
	sta symbolNameLength
.scan:
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
	jmp .scan
.lookup:
	lda symbolNameLength
	beq .bad

	;; Symbol routines borrow ZP_PTR0; preserve the value cursor explicitly.
	lda ZP_PTR0
	pha
	lda ZP_PTR0+1
	pha
	jsr findSymbolEntry
	bcc .intern
	lda symbolKind
	cmp #SYMBOL_LABEL_UNDEFINED
	beq .label
	lda symbolValue
	sta valueAtom
	lda symbolValue+1
	sta valueAtom+1
	lda #VALUE_ATOM_FIXED
	sta valueAtomKind
	jmp .okRestore

.intern:
	jsr internLabel
	bcc .internError
.label:
	lda symbolEntry
	sta valueAtomSymbol
	lda symbolEntry+1
	sta valueAtomSymbol+1
	lda #VALUE_ATOM_LABEL
	sta valueAtomKind
.okRestore:
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0
	sec
	rts

.internError:
	cmp #SYMBOL_FULL
	beq .fullRestore
	cmp #SYMBOL_NO_SCOPE
	beq .scopeRestore
	jmp .badRestore
.fullRestore:
	lda #VALUE_SYMBOL_FULL
	sta valueStatus
	jmp .failRestore
.scopeRestore:
	lda #VALUE_SCOPE_ERROR
	sta valueStatus
	jmp .failRestore
.badRestore:
	lda #VALUE_BAD
	sta valueStatus
.failRestore:
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0
	clc
	rts
.bad:
	lda #VALUE_BAD
	sta valueStatus
	clc
	rts

;;; applyValuePrefix
;;; Apply < or > to a fixed result. Forward fixups apply the same operation when
;;; their label is eventually defined.
applyValuePrefix:
	lda capturedPrefix
	beq .done
	cmp #VALUE_PREFIX_LOW
	beq .low
	lda valueResult+1
	sta valueResult
.low:
	lda #$00
	sta valueResult+1
.done:
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

;;; Persistent parse result only when VALUE_UNRESOLVED is returned.
capturedHasSymbol:	byte 0
capturedSymbol:		word 0
capturedAddend:		word 0
capturedPrefix:		byte 0

;;; Small explicit parser state.
valueLeft:		byte 0
valueAtom:		word 0
valueTemp:		word 0
valueOperator:		byte 0
valueAtomKind:		byte 0
valueAtomSymbol:	word 0
valueStatus:		byte 0
