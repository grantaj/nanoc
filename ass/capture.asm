;;; capture.asm
;;;
;;; Reduce the existing tiny value grammar to the only persistent recipe needed
;;; after a source line disappears:
;;;
;;;     fixed 16-bit value
;;; or  one label entry + 16-bit addend + optional < / > prefix
;;;
;;; There is still no expression tree. Two symbolic atoms, or literal-symbol
;;; subtraction, are rejected because nanoc's source does not require them.

VALUE_SYMBOL_FULL = $03
VALUE_SCOPE_ERROR = $04

CAPTURE_ATOM_FIXED = $00
CAPTURE_ATOM_LABEL = $01

;;; captureValue
;;;
;;; Input: ZP_PTR0/X = complete value text.
;;; Output:
;;;   VALUE_OK         -> valueResult is fixed and layout-independent
;;;   VALUE_UNRESOLVED -> captured* describes one label-dependent value
;;;   VALUE_BAD / VALUE_SYMBOL_FULL / VALUE_SCOPE_ERROR
;;;
;;; Labels remain deferred even when already defined: an earlier long->short
;;; relaxation can still move their final addresses.
captureValue:
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
	sta capturedRelaxSafe
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
	jsr captureAtom
	bcs .firstAtomOk
	jmp .atomError
.firstAtomOk:
	lda captureAtomKind
	cmp #CAPTURE_ATOM_LABEL
	beq .firstLabel
	lda valueAtom
	sta capturedAddend
	lda valueAtom+1
	sta capturedAddend+1
	jmp .operator
.firstLabel:
	lda #$01
	sta capturedHasSymbol
	sta capturedRelaxSafe		; bare label address only moves downward
	lda captureAtomSymbol
	sta capturedSymbol
	lda captureAtomSymbol+1
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
	sta captureOperator
	jsr advanceValue
	jsr captureAtom
	bcs .secondAtomOk
	jmp .atomError
.secondAtomOk:
	lda valueLeft
	beq .operatorDone
	jmp .bad			; exactly zero or one binary operation
.operatorDone:
	lda captureAtomKind
	cmp #CAPTURE_ATOM_LABEL
	beq .secondLabel

	;; Second atom is fixed. It is simply the addend to a label, or ordinary
	;; 16-bit arithmetic when the first atom was also fixed.
	lda captureOperator
	cmp #'+'
	beq .addFixed
	sec
	lda capturedAddend
	sbc valueAtom
	sta capturedAddend
	lda capturedAddend+1
	sbc valueAtom+1
	sta capturedAddend+1
	lda capturedHasSymbol
	beq .finish
	lda #$00			; arithmetic may wrap, so keep direct mode conservative
	sta capturedRelaxSafe
	jmp .finish
.addFixed:
	clc
	lda capturedAddend
	adc valueAtom
	sta capturedAddend
	lda capturedAddend+1
	adc valueAtom+1
	sta capturedAddend+1
	lda capturedHasSymbol
	beq .finish
	lda #$00			; label+literal is resolved, but not width-relaxed
	sta capturedRelaxSafe
	jmp .finish

.secondLabel:
	lda capturedHasSymbol
	bne .bad			; no symbol +/- symbol machinery
	lda captureOperator
	cmp #'+'
	bne .bad			; literal - symbol is deliberately unsupported
	lda #$01
	sta capturedHasSymbol
	lda #$00			; any binary arithmetic stays conservatively long
	sta capturedRelaxSafe
	lda captureAtomSymbol
	sta capturedSymbol
	lda captureAtomSymbol+1
	sta capturedSymbol+1

.finish:
	lda capturedHasSymbol
	bne .deferred
	lda capturedAddend
	sta valueResult
	lda capturedAddend+1
	sta valueResult+1
	jsr applyCapturePrefix
	lda #VALUE_OK
	rts

.deferred:
	lda capturedPrefix
	beq .unresolved
	lda #$01			; <label and >label are always one-byte results
	sta capturedRelaxSafe
.unresolved:
	lda #VALUE_UNRESOLVED
	rts

.atomError:
	lda captureStatus
	rts
.bad:
	lda #VALUE_BAD
	rts

;;; captureAtom
;;; Consume one atom. Fixed atoms use valueAtom; labels use captureAtomSymbol.
;;; Carry clear returns captureStatus.
captureAtom:
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
	cmp #39
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
	jmp captureSymbolAtom
.decimal:
	jsr parseDecimalAtom
	bcc .bad
.fixed:
	lda #CAPTURE_ATOM_FIXED
	sta captureAtomKind
	sec
	rts
.bad:
	lda #VALUE_BAD
	sta captureStatus
	clc
	rts

;;; captureSymbolAtom
;;; Keep only the symbol-table entry, never the source text. Existing constants
;;; collapse to fixed values; labels (defined or not) remain layout-dependent.
captureSymbolAtom:
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

	lda ZP_PTR0
	pha
	lda ZP_PTR0+1
	pha
	jsr findSymbolEntry
	bcc .intern
	lda symbolFlags
	and #SYMBOL_FLAG_LABEL
	bne .label
	lda symbolFlags
	and #SYMBOL_FLAG_DEFINED
	beq .badRestore
	lda symbolValue
	sta valueAtom
	lda symbolValue+1
	sta valueAtom+1
	lda #CAPTURE_ATOM_FIXED
	sta captureAtomKind
	jmp .okRestore

.intern:
	jsr internLabel
	bcc .internError
.label:
	lda symbolEntry
	sta captureAtomSymbol
	lda symbolEntry+1
	sta captureAtomSymbol+1
	lda #CAPTURE_ATOM_LABEL
	sta captureAtomKind
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
	sta captureStatus
	jmp .failRestore
.scopeRestore:
	lda #VALUE_SCOPE_ERROR
	sta captureStatus
	jmp .failRestore
.badRestore:
	lda #VALUE_BAD
	sta captureStatus
.failRestore:
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0
	clc
	rts
.bad:
	lda #VALUE_BAD
	sta captureStatus
	clc
	rts

;;; applyCapturePrefix
;;; Apply < or > to fixed valueResult. Deferred values apply it after layout.
applyCapturePrefix:
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

capturedHasSymbol:	byte 0
capturedSymbol:		word 0
capturedAddend:		word 0
capturedPrefix:		byte 0
capturedRelaxSafe:	byte 0

captureOperator:	byte 0
captureAtomKind:	byte 0
captureAtomSymbol:	word 0
captureStatus:		byte 0
