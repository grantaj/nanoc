;;; symbols.asm
;;;
;;; A deliberately small linear symbol table.
;;;
;;; Symbol names are not copied. Each entry points back into the resident source
;;; buffer and stores only name length, 16-bit value, and local-label scope.

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

;;; resetSymbols
;;; Empty the caller-owned table.
resetSymbols:
	lda symbolTableStart
	sta symbolTableEnd
	lda symbolTableStart+1
	sta symbolTableEnd+1
	rts

;;; defineSymbol
;;;
;;; Input:
;;;   symbolName / symbolNameLength
;;;   symbolValue
;;;
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

	;; The next entry must still fit inside [symbolTableStart, symbolTableLimit).
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
;;; Look up symbolName/symbolNameLength. Ordinary names have scope zero;
;;; `.local` names use currentScope.
;;;
;;; Returns symbolValue and carry set when found, carry clear otherwise.
;;; ZP_PTR1 is preserved because it is the assembler's source pointer.
;;; ZP_PTR0, A, X and Y are clobbered.
findSymbol:
	jsr symbolScope
	bcs .scopeReady
	clc
	rts
.scopeReady:
	sta symbolWantedScope

	;; The requested name is one zero-copy source view.
	lda symbolName
	sta ZP_PTR0
	lda symbolName+1
	sta ZP_PTR0+1

	;; Borrow ZP_PTR1 while walking the table, but give the source pointer back.
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
	beq .notFound

.entry:
	lda symbolScan
	sta ZP_PTR1
	lda symbolScan+1
	sta ZP_PTR1+1

	ldy #SYMBOL_LENGTH
	lda (ZP_PTR1),y
	cmp symbolNameLength
	bne .advance
	ldy #SYMBOL_SCOPE
	lda (ZP_PTR1),y
	cmp symbolWantedScope
	bne .advance

	;; Point ZP_PTR1 at the stored source text and compare the names in place.
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

	;; Reload the table entry and return its 16-bit value.
	lda symbolScan
	sta ZP_PTR1
	lda symbolScan+1
	sta ZP_PTR1+1
	ldy #SYMBOL_VALUE_LO
	lda (ZP_PTR1),y
	sta symbolValue
	iny
	lda (ZP_PTR1),y
	sta symbolValue+1
	sec
	jmp .restoreSource

.advance:
	clc
	lda symbolScan
	adc #SYMBOL_SIZE
	sta symbolScan
	bcc .next
	inc symbolScan+1
	jmp .next

.notFound:
	clc
.restoreSource:
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	rts

;;; symbolScope
;;; Return this name's scope in A/carry set. A local name before any global
;;; label has no scope and returns carry clear.
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

;;; Caller-owned table region and current local-label scope.
symbolTableStart:	word 0
symbolTableEnd:		word 0
symbolTableLimit:	word 0
currentScope:		byte 0

;;; Symbol query/result state.
symbolName:		word 0
symbolNameLength:	byte 0
symbolValue:		word 0

;;; Scratch used only while walking/appending the table.
symbolWantedScope:	byte 0
symbolNext:		word 0
symbolScan:		word 0
