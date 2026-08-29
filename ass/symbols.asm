;;; symbols.asm
;;;
;;; A deliberately small linear symbol table whose names survive source input.
;;;
;;; Entries grow upward from symbolTableStart while owned name bytes grow
;;; downward from symbolTableLimit. The two regions simply meet when full.

SYMBOL_NAME_LO   = 0
SYMBOL_NAME_HI   = 1
SYMBOL_LENGTH    = 2
SYMBOL_BASE_LO   = 3
SYMBOL_BASE_HI   = 4
SYMBOL_VALUE_LO  = 5
SYMBOL_VALUE_HI  = 6
SYMBOL_SCOPE     = 7
SYMBOL_KIND      = 8
SYMBOL_SIZE      = 9

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
	lda #$00
	sta symbolBase
	sta symbolBase+1
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
	sta symbolBase
	sta symbolBase+1
	sta symbolValue
	sta symbolValue+1
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
;;; Define a label at the current conservative assemblyPtr. A previous forward
;;; reference may already have created its undefined entry.
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
	ldy #SYMBOL_BASE_LO
	lda assemblyPtr
	sta (ZP_PTR0),y
	iny
	lda assemblyPtr+1
	sta (ZP_PTR0),y
	iny
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
	sta symbolBase
	sta symbolValue
	lda assemblyPtr+1
	sta symbolBase+1
	sta symbolValue+1
	lda #SYMBOL_OK
	rts

.new:
	lda assemblyPtr
	sta symbolBase
	sta symbolValue
	lda assemblyPtr+1
	sta symbolBase+1
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

;;; findConstant
;;; Fixed-value lookup used by parseValue. Labels deliberately do not resolve
;;; here: even a backward label can move when an earlier instruction shortens.
findConstant:
	jsr findSymbolEntry
	bcc .notFound
	lda symbolKind
	cmp #SYMBOL_CONSTANT
	bne .notFound
	sec
	rts
.notFound:
	clc
	rts

;;; findSymbolEntry
;;; Look up symbolName/symbolNameLength in the current local-label scope.
;;; Carry set returns symbolEntry, symbolBase, symbolValue, and symbolKind.
;;; ZP_PTR1 is preserved because it is normally the source cursor.
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
	ldy #SYMBOL_BASE_LO
	lda (ZP_PTR1),y
	sta symbolBase
	iny
	lda (ZP_PTR1),y
	sta symbolBase+1
	iny
	lda (ZP_PTR1),y
	sta symbolValue
	iny
	lda (ZP_PTR1),y
	sta symbolValue+1
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
;;; Inputs: symbolName/Length, symbolBase, symbolValue, symbolKind.
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
	lda symbolBase
	sta (ZP_PTR1),y
	iny
	lda symbolBase+1
	sta (ZP_PTR1),y
	iny
	lda symbolValue
	sta (ZP_PTR1),y
	iny
	lda symbolValue+1
	sta (ZP_PTR1),y
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

;;; updateLabelValues
;;; Recompute defined labels by subtracting each earlier direct instruction that
;;; has shortened from three bytes to two.
updateLabelValues:
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
	beq .done
.entry:
	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_KIND
	lda (ZP_PTR0),y
	cmp #SYMBOL_LABEL_DEFINED
	bne .advance
	ldy #SYMBOL_BASE_LO
	lda (ZP_PTR0),y
	sta adjustInput
	iny
	lda (ZP_PTR0),y
	sta adjustInput+1
	jsr adjustAddress
	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_VALUE_LO
	lda adjustResult
	sta (ZP_PTR0),y
	iny
	lda adjustResult+1
	sta (ZP_PTR0),y
.advance:
	clc
	lda symbolScan
	adc #SYMBOL_SIZE
	sta symbolScan
	bcc .samePage
	inc symbolScan+1
.samePage:
	jmp .next
.done:
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
;;; symbolEntry -> symbolValue/symbolKind.
loadSymbolEntry:
	lda symbolEntry
	sta ZP_PTR0
	lda symbolEntry+1
	sta ZP_PTR0+1
	ldy #SYMBOL_VALUE_LO
	lda (ZP_PTR0),y
	sta symbolValue
	iny
	lda (ZP_PTR0),y
	sta symbolValue+1
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
symbolBase:		word 0
symbolValue:		word 0
symbolKind:		byte 0

symbolWantedScope:	byte 0
symbolNext:		word 0
symbolNewName:		word 0
symbolScan:		word 0
