;;; symbols.asm
;;;
;;; The caller supplies one fixed symbol workspace. Two linear tables use it from
;;; opposite ends:
;;;
;;;   ordinary names grow upward and live for the whole assembly;
;;;   dot-prefixed names grow downward and live only for the current global label.
;;;
;;; Starting a new global scope checks that every local forward reference has
;;; resolved, then rewinds the local pointer to the top of the workspace. There is
;;; no partition to tune, no allocator, no compaction, and nothing is individually
;;; freed. The tables are full only when their two moving ends meet.
;;;
;;; Each record is simply:
;;;   byte  name length
;;;   word  value or unresolved-reference head
;;;   byte  kind
;;;   byte[] name
;;;
;;; The name follows its entry, so storing another two-byte pointer to it would be
;;; redundant. Records are never moved while live, so symbolEntry remains stable
;;; for staged fixups. The table direction itself says whether a name is global
;;; or local.
;;;
;;; The two-byte payload has one meaning at a time:
;;;   constant / defined label -> final value
;;;   undefined label          -> head of its staged 16-bit reference chain
;;; An undefined label has no value yet, and a defined label has no outstanding
;;; word references, so keeping both would waste two bytes in every symbol.

SYMBOL_LENGTH      = 0
SYMBOL_PAYLOAD_LO  = 1
SYMBOL_PAYLOAD_HI  = 2
SYMBOL_KIND        = 3
SYMBOL_NAME        = 4
SYMBOL_HEADER_SIZE = 4

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

;;; These select one of the two table directions; they are not stored in records.
SYMBOL_SCOPE_GLOBAL = $00
SYMBOL_SCOPE_LOCAL  = $01

;;; resetSymbols
;;; Empty both tables. The local table remains unavailable until the first global
;;; label gives dot-prefixed names a scope.
resetSymbols:
	lda symbolTableStart
	sta symbolTableEnd
	lda symbolTableStart+1
	sta symbolTableEnd+1
	jsr resetLocalSymbols
	lda #$00
	sta currentScope
	rts

;;; resetLocalSymbols
;;; Rewind current-scope scratch to the top of the shared workspace. No bytes are
;;; cleared; the pointer alone defines which local records are live.
resetLocalSymbols:
	lda symbolTableLimit
	sta localSymbolTableEnd
	lda symbolTableLimit+1
	sta localSymbolTableEnd+1
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
;;; Define a label at the current final assemblyPtr. A non-local label first ends
;;; the previous local-label lifetime; that scratch table is rewound only after
;;; every local forward reference has been resolved.
defineLabel:
	jsr prepareLabelLifetime
	bcc .noScope
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

;;; prepareLabelLifetime
;;; `enterLabelScope` in assembler.asm still performs the cheap syntactic check
;;; that a local label has a preceding global label. Here a global definition
;;; performs the actual lifetime transition: validate old locals, rewind their
;;; scratch table, and leave currentScope nonzero for following dot labels.
prepareLabelLifetime:
	lda symbolNameLength
	beq .bad
	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'.'
	beq .ok
	jsr allLocalLabelsDefined
	bcc .bad
	jsr resetLocalSymbols
	lda #$01
	sta currentScope
.ok:
	sec
	rts
.bad:
	clc
	rts

;;; findSymbolEntry
;;; Ordinary names are searched upward through the persistent table. Dot-prefixed
;;; names are searched upward through the live local records at the top of the
;;; workspace. ZP_PTR1 is preserved.
findSymbolEntry:
	jsr symbolScope
	bcs .scopeReady
	clc
	rts
.scopeReady:
	sta symbolWantedScope
	beq .global
	lda localSymbolTableEnd
	sta symbolScan
	lda localSymbolTableEnd+1
	sta symbolScan+1
	lda symbolTableLimit
	sta symbolSearchEnd
	lda symbolTableLimit+1
	sta symbolSearchEnd+1
	jmp .save
.global:
	lda symbolTableStart
	sta symbolScan
	lda symbolTableStart+1
	sta symbolScan+1
	lda symbolTableEnd
	sta symbolSearchEnd
	lda symbolTableEnd+1
	sta symbolSearchEnd+1
.save:
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha

.next:
	lda symbolScan
	cmp symbolSearchEnd
	bne .entry
	lda symbolScan+1
	cmp symbolSearchEnd+1
	bne .entry
	jmp .notFound

.entry:
	lda symbolScan
	sta ZP_PTR1
	lda symbolScan+1
	sta ZP_PTR1+1
	ldy #SYMBOL_LENGTH
	lda (ZP_PTR1),y
	sta symbolRecordLength
	cmp symbolNameLength
	bne .advance

	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	clc
	lda symbolScan
	adc #SYMBOL_NAME
	sta ZP_PTR1
	lda symbolScan+1
	adc #$00
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
	lda symbolRecordLength
	clc
	adc #SYMBOL_HEADER_SIZE
	sta symbolRecordSize
	clc
	lda symbolScan
	adc symbolRecordSize
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
;;; Persistent records append upward from symbolTableStart. Local records prepend
;;; downward from symbolTableLimit. Both remain stable while live; allocation
;;; fails only if the proposed record would cross the other table's current end.
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
	lda symbolNameLength
	clc
	adc #SYMBOL_HEADER_SIZE
	bcc .sizeReady
	jmp .full
.sizeReady:
	sta symbolRecordSize
	lda symbolWantedScope
	beq .global

.local:
	sec
	lda localSymbolTableEnd
	sbc symbolRecordSize
	sta symbolNext
	lda localSymbolTableEnd+1
	sbc #$00
	sta symbolNext+1
	bcs .localNoUnderflow
	jmp .full
.localNoUnderflow:

	;;; The new local record may touch, but not cross, the persistent end.
	lda symbolNext+1
	cmp symbolTableEnd+1
	bcs .localHighEnough
	jmp .full
.localHighEnough:
	bne .localRoom
	lda symbolNext
	cmp symbolTableEnd
	bcs .localRoom
	jmp .full
.localRoom:
	lda symbolNext
	sta symbolAllocEnd
	lda symbolNext+1
	sta symbolAllocEnd+1
	jmp .write

.global:
	clc
	lda symbolTableEnd
	adc symbolRecordSize
	sta symbolNext
	lda symbolTableEnd+1
	adc #$00
	sta symbolNext+1
	bcc .globalNoOverflow
	jmp .full
.globalNoOverflow:

	;;; The new persistent record may touch, but not cross, the live local end.
	lda symbolNext+1
	cmp localSymbolTableEnd+1
	bcc .globalRoom
	beq .globalSamePage
	jmp .full
.globalSamePage:
	lda symbolNext
	cmp localSymbolTableEnd
	bcc .globalRoom
	beq .globalRoom
	jmp .full
.globalRoom:
	lda symbolTableEnd
	sta symbolAllocEnd
	lda symbolTableEnd+1
	sta symbolAllocEnd+1

.write:
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha

	lda symbolAllocEnd
	sta symbolEntry
	sta ZP_PTR1
	lda symbolAllocEnd+1
	sta symbolEntry+1
	sta ZP_PTR1+1
	ldy #SYMBOL_LENGTH
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
	lda symbolKind
	sta (ZP_PTR1),y

	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1
	clc
	lda symbolEntry
	adc #SYMBOL_NAME
	sta ZP_PTR1
	lda symbolEntry+1
	adc #$00
	sta ZP_PTR1+1
	ldy #$00
.copyName:
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	iny
	cpy symbolNameLength
	bne .copyName

	lda symbolWantedScope
	beq .commitGlobal
	lda symbolNext
	sta localSymbolTableEnd
	lda symbolNext+1
	sta localSymbolTableEnd+1
	jmp .committed
.commitGlobal:
	lda symbolNext
	sta symbolTableEnd
	lda symbolNext+1
	sta symbolTableEnd+1
.committed:
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
;;; Carry set only when both assembly-lifetime globals and the current local
;;; scratch table contain no unresolved labels.
allLabelsDefined:
	lda symbolTableStart
	sta symbolScan
	lda symbolTableStart+1
	sta symbolScan+1
	lda symbolTableEnd
	sta symbolSearchEnd
	lda symbolTableEnd+1
	sta symbolSearchEnd+1
	jsr scanLabelsDefined
	bcc .bad
	jmp allLocalLabelsDefined
.bad:
	clc
	rts

;;; allLocalLabelsDefined
;;; Used both at EOF and immediately before the scratch table is rewound.
allLocalLabelsDefined:
	lda localSymbolTableEnd
	sta symbolScan
	lda localSymbolTableEnd+1
	sta symbolScan+1
	lda symbolTableLimit
	sta symbolSearchEnd
	lda symbolTableLimit+1
	sta symbolSearchEnd+1

scanLabelsDefined:
.next:
	lda symbolScan
	cmp symbolSearchEnd
	bne .entry
	lda symbolScan+1
	cmp symbolSearchEnd+1
	beq .ok
.entry:
	lda symbolScan
	sta ZP_PTR0
	lda symbolScan+1
	sta ZP_PTR0+1
	ldy #SYMBOL_LENGTH
	lda (ZP_PTR0),y
	sta symbolRecordLength
	ldy #SYMBOL_KIND
	lda (ZP_PTR0),y
	cmp #SYMBOL_LABEL_UNDEFINED
	beq .bad
	lda symbolRecordLength
	clc
	adc #SYMBOL_HEADER_SIZE
	sta symbolRecordSize
	clc
	lda symbolScan
	adc symbolRecordSize
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
;;; Ordinary names have assembly lifetime. `.name` has current-global-label
;;; lifetime and therefore requires a preceding global label.
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
	lda #SYMBOL_SCOPE_GLOBAL
	sec
	rts
.local:
	lda currentScope
	beq .bad
	lda #SYMBOL_SCOPE_LOCAL
	sec
	rts
.bad:
	clc
	rts

;;; Shared workspace lower edge, persistent end, and fixed upper edge.
symbolTableStart:	word 0
symbolTableEnd:		word 0
symbolTableLimit:	word 0

;;; Current lower edge of the local records growing down from symbolTableLimit.
localSymbolTableEnd:	word 0

;;; Compatibility variables while old direct fixtures stop configuring a
;;; separate local range. symbols.asm does not consult either value.
localSymbolTableStart:	word 0
localSymbolTableLimit:	word 0

;;; Zero means no global label has appeared yet. Nonzero means dot-prefixed names
;;; have a current scope. It is reset to one at every global definition.
currentScope:		byte 0

symbolName:		word 0
symbolNameLength:	byte 0
symbolEntry:		word 0
symbolValue:		word 0
symbolRefs:		word 0
symbolKind:		byte 0

symbolWantedScope:	byte 0
symbolNext:		word 0
symbolScan:		word 0
symbolSearchEnd:	word 0
symbolAllocEnd:		word 0
symbolRecordLength:	byte 0
symbolRecordSize:	byte 0
referencePtr:		word 0
referenceNext:		word 0
