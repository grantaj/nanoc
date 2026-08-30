;;; symbols.asm
;;;
;;; A deliberately small linear symbol table whose names survive source input.
;;;
;;; Entries grow upward from symbolTableStart while owned name bytes grow
;;; downward from symbolTableLimit. The two regions simply meet when full.
;;;
;;; The two-byte payload has one meaning at a time:
;;;   constant / defined label -> final value
;;;   undefined label          -> head of its staged 16-bit reference chain
;;; An undefined label has no value yet, and a defined label has no outstanding
;;; word references, so keeping both would waste two bytes in every symbol.

SYMBOL_NAME_LO    = 0
SYMBOL_NAME_HI    = 1
SYMBOL_LENGTH     = 2
SYMBOL_PAYLOAD_LO = 3
SYMBOL_PAYLOAD_HI = 4
SYMBOL_SCOPE      = 5
SYMBOL_KIND       = 6
SYMBOL_SIZE       = 7

SYMBOL_VALUE_LO = SYMBOL_PAYLOAD_LO
SYMBOL_VALUE_HI = SYMBOL_PAYLOAD_HI
SYMBOL_REFS_LO  = SYMBOL_PAYLOAD_LO
SYMBOL_REFS_HI  = SYMBOL_PAYLOAD_HI

SYMBOL_CONSTANT        = $00
SYMBOL_LABEL_UNDEFINED = $01
SYMBOL_LABEL_DEFINED   = $02

SYMBOL_OK        = $00
SYMBOL_DUPLICATE = $01
SYMBOL_FULL      = $02
SYMBOL_NO_SCOPE  = $03

;;; resetSymbols
;;; Empty the caller-owned table and return the name cursor to its upper end.
resetSymbols:
	lda symbolTableStart
	sta symbolTableEnd
	lda symbolTableStart+1
	sta symbolTableEnd+1
	lda symbolTableLimit
	sta symbolNameEnd
	lda symbolTableLimit+1
	sta symbolNameEnd+1
	rts

;;; defineConstant
;;; Define a fixed constant. Input is symbolName/symbolNameLength/symbolValue.
defineConstant:
	jsr symbolScope
	bcc .noScope
	jsr findSymbolEntry
	bcs .duplicate
	lda #SYMBOL_CONSTANT
	sta symbolKind
	jsr allocateSymbol
	rts
.duplicate:
	lda #SYMBOL_DUPLICATE
	rts
.noScope:
	lda #SYMBOL_NO_SCOPE
	rts

;;; internLabel
;;; Return an existing label entry or create one undefined entry with an owned
;;; name. Carry set means success and symbolEntry identifies the entry.
internLabel:
	jsr symbolScope
	bcc .noScope
	jsr findSymbolEntry
	bcc .new
	lda symbolKind
	cmp #SYMBOL_CONSTANT
	beq .duplicate
	lda #SYMBOL_OK
	sec
	rts
.new:
	lda #$00
	sta symbolRefs
	sta symbolRefs+1
	lda #SYMBOL_LABEL_UNDEFINED
	sta symbolKind
	jsr allocateSymbol
	cmp #SYMBOL_OK
	bne .failed
	sec
	rts
.failed:
	clc
	rts
.duplicate:
	lda #SYMBOL_DUPLICATE
	clc
	rts
.noScope:
	lda #SYMBOL_NO_SCOPE
	clc
	rts

;;; defineLabel
;;; Define a label at the current final assemblyPtr. For an existing undefined
;;; entry, findSymbolEntry leaves its old reference-chain head in symbolRefs.
;;; Replace the shared payload with the final value, mark the label defined, and
;;; consume that old chain immediately. The payload changes meaning in one place.
defineLabel:
	jsr symbolScope
	bcc .noScope
	jsr findSymbolEntry
	bcc .new
	lda symbolKind
	cmp #SYMBOL_LABEL_UNDEFINED
	bne .duplicate

	lda symbolEntry
	sta ZP_PTR0
	lda symbolEntry+1
	sta ZP_PTR0+1
	ldy #SYMBOL_VALUE_LO
	lda assemblyPtr
	sta (ZP_PTR0),y
	iny
	lda assemblyPtr+1
	sta (ZP_PTR0),y
	ldy #SYMBOL_KIND
	lda #SYMBOL_LABEL_DEFINED
	sta (ZP_PTR0),y
	sta symbolKind
	lda assemblyPtr
	sta symbolValue
	lda assemblyPtr+1
	sta symbolValue+1
	jsr resolveWordReferencesForSymbol
	lda #SYMBOL_OK
	rts

.new:
	lda #$00
	sta symbolRefs
	sta symbolRefs+1
	lda assemblyPtr
	sta symbolValue
	lda assemblyPtr+1
	sta symbolValue+1
	lda #SYMBOL_LABEL_DEFINED
	sta symbolKind
	jsr allocateSymbol
	rts
.duplicate:
	lda #SYMBOL_DUPLICATE
	rts
.noScope:
	lda #SYMBOL_NO_SCOPE
	rts

;;; findSymbolEntry
;;; Look up symbolName/symbolNameLength in the current local-label scope.
;;; The entry payload is copied to both symbolValue and symbolRefs; symbolKind
;;; tells the caller which interpretation is meaningful. ZP_PTR1 is preserved.
findSymbolEntry:
	jsr symbolScope
	bcs .scopeReady
	clc
	rts
.scopeReady:
	sta symbolWantedScope

	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha

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
	sta ZP_PTR1
	lda symbolScan+1
	sta ZP_PTR1+1
	ldy #SYMBOL_LENGTH
	lda (ZP_PTR1),y
	cmp symbolNameLength
	beq .lengthMatches
	jmp .advance
.lengthMatches:
	ldy #SYMBOL_SCOPE
	lda (ZP_PTR1),y
	cmp symbolWantedScope
	beq .scopeMatches
	jmp .advance
.scopeMatches:
	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	ldy #SYMBOL_NAME_LO
	lda (ZP_PTR1),y
	tax
	iny
	lda (ZP_PTR1),y
	sta ZP_PTR1+1
	stx ZP_PTR1
	ldy #$00
.compare:
	lda (ZP_PTR0),y
	cmp (ZP_PTR1),y
	bne .advance
	iny
	cpy symbolNameLength
	bne .compare

	lda symbolScan
	sta symbolEntry
	sta ZP_PTR1
	lda symbolScan+1
	sta symbolEntry+1
	sta ZP_PTR1+1
	ldy #SYMBOL_PAYLOAD_LO
	lda (ZP_PTR1),y
	sta symbolValue
	sta symbolRefs
	iny
	lda (ZP_PTR1),y
	sta symbolValue+1
	sta symbolRefs+1
	ldy #SYMBOL_KIND
	lda (ZP_PTR1),y
	sta symbolKind
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	sec
	rts

.advance:
	clc
	lda symbolScan
	adc #SYMBOL_SIZE
	sta symbolScan
	bcc .samePage
	inc symbolScan+1
.samePage:
	jmp .next

.notFound:
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	clc
	rts

;;; allocateSymbol
;;; Append one entry and copy its name into the downward-growing name area.
;;; Undefined labels store symbolRefs in the payload; everything else stores
;;; symbolValue.
allocateSymbol:
	lda symbolNameLength
	bne .hasName
	jmp .noScope
.hasName:
	jsr symbolScope
	bcs .hasScope
	jmp .noScope
.hasScope:
	sta symbolWantedScope

	clc
	lda symbolTableEnd
	adc #SYMBOL_SIZE
	sta symbolNext
	lda symbolTableEnd+1
	adc #$00
	sta symbolNext+1

	sec
	lda symbolNameEnd
	sbc symbolNameLength
	sta symbolNewName
	lda symbolNameEnd+1
	sbc #$00
	sta symbolNewName+1

	lda symbolNewName+1
	cmp symbolNext+1
	bcs .highRoom
	jmp .full
.highRoom:
	bne .room
	lda symbolNewName
	cmp symbolNext
	bcs .room
	jmp .full
.room:
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha

	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	lda symbolNewName
	sta ZP_PTR1
	lda symbolNewName+1
	sta ZP_PTR1+1
	ldy #$00
.copyName:
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	iny
	cpy symbolNameLength
	bne .copyName

	lda symbolTableEnd
	sta symbolEntry
	sta ZP_PTR1
	lda symbolTableEnd+1
	sta symbolEntry+1
	sta ZP_PTR1+1
	ldy #SYMBOL_NAME_LO
	lda symbolNewName
	sta (ZP_PTR1),y
	iny
	lda symbolNewName+1
	sta (ZP_PTR1),y
	iny
	lda symbolNameLength
	sta (ZP_PTR1),y
	iny
	lda symbolKind
	cmp #SYMBOL_LABEL_UNDEFINED
	beq .storeRefs
	lda symbolValue
	sta (ZP_PTR1),y
	iny
	lda symbolValue+1
	sta (ZP_PTR1),y
	jmp .storedPayload
.storeRefs:
	lda symbolRefs
	sta (ZP_PTR1),y
	iny
	lda symbolRefs+1
	sta (ZP_PTR1),y
.storedPayload:
	iny
	lda symbolWantedScope
	sta (ZP_PTR1),y
	iny
	lda symbolKind
	sta (ZP_PTR1),y

	lda symbolNext
	sta symbolTableEnd
	lda symbolNext+1
	sta symbolTableEnd+1
	lda symbolNewName
	sta symbolNameEnd
	lda symbolNewName+1
	sta symbolNameEnd+1

	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	lda #SYMBOL_OK
	rts
.full:
	lda #SYMBOL_FULL
	rts
.noScope:
	lda #SYMBOL_NO_SCOPE
	rts

;;; linkWordReference
;;; referencePtr identifies two staged operand bytes for an unresolved plain
;;; label. Those bytes temporarily point to the previous reference, and the same
;;; two-byte symbol payload becomes the new chain head.
linkWordReference:
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha

	lda symbolEntry
	sta ZP_PTR0
	lda symbolEntry+1
	sta ZP_PTR0+1
	ldy #SYMBOL_REFS_LO
	lda (ZP_PTR0),y
	sta referenceNext
	iny
	lda (ZP_PTR0),y
	sta referenceNext+1

	lda referencePtr
	sta ZP_PTR1
	lda referencePtr+1
	sta ZP_PTR1+1
	ldy #$00
	lda referenceNext
	sta (ZP_PTR1),y
	iny
	lda referenceNext+1
	sta (ZP_PTR1),y

	lda symbolEntry
	sta ZP_PTR0
	lda symbolEntry+1
	sta ZP_PTR0+1
	ldy #SYMBOL_REFS_LO
	lda referencePtr
	sta (ZP_PTR0),y
	iny
	lda referencePtr+1
	sta (ZP_PTR0),y

	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	rts

;;; resolveWordReferencesForSymbol
;;; symbolRefs is the chain head captured by defineLabel before the entry payload
;;; changed to the final value. Patch every staged link immediately.
resolveWordReferencesForSymbol:
	lda symbolRefs
	sta referencePtr
	lda symbolRefs+1
	sta referencePtr+1
.reference:
	lda referencePtr
	ora referencePtr+1
	beq .done
	lda referencePtr
	sta ZP_PTR0
	lda referencePtr+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	sta referenceNext
	iny
	lda (ZP_PTR0),y
	sta referenceNext+1
	dey
	lda symbolValue
	sta (ZP_PTR0),y
	iny
	lda symbolValue+1
	sta (ZP_PTR0),y
	lda referenceNext
	sta referencePtr
	lda referenceNext+1
	sta referencePtr+1
	jmp .reference
.done:
	lda #$00
	sta symbolRefs
	sta symbolRefs+1
	rts

;;; allLabelsDefined
;;; Carry set unless an interned label was never defined.
allLabelsDefined:
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
	beq .ok
.entry:
	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_KIND
	lda (ZP_PTR0),y
	cmp #SYMBOL_LABEL_UNDEFINED
	beq .bad
.advance:
	clc
	lda symbolScan
	adc #SYMBOL_SIZE
	sta symbolScan
	bcc .samePage
	inc symbolScan+1
.samePage:
	jmp .next
.ok:
	sec
	rts
.bad:
	clc
	rts

;;; loadSymbolEntry
;;; Copy the shared payload to both interpretations; symbolKind tells the caller
;;; whether it is a final value or an unresolved-reference head.
loadSymbolEntry:
	lda symbolEntry
	sta ZP_PTR0
	lda symbolEntry+1
	sta ZP_PTR0+1
	ldy #SYMBOL_PAYLOAD_LO
	lda (ZP_PTR0),y
	sta symbolValue
	sta symbolRefs
	iny
	lda (ZP_PTR0),y
	sta symbolValue+1
	sta symbolRefs+1
	ldy #SYMBOL_KIND
	lda (ZP_PTR0),y
	sta symbolKind
	rts

;;; symbolScope
;;; Ordinary names have scope zero. `.name` uses currentScope.
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

symbolTableStart:	word 0
symbolTableEnd:		word 0
symbolTableLimit:	word 0
symbolNameEnd:		word 0
currentScope:		byte 0

symbolName:		word 0
symbolNameLength:	byte 0
symbolEntry:		word 0
symbolValue:		word 0
symbolRefs:		word 0
symbolKind:		byte 0

symbolWantedScope:	byte 0
symbolNext:		word 0
symbolNewName:		word 0
symbolScan:		word 0
referencePtr:		word 0
referenceNext:		word 0
