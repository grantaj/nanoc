;;; representation.asm
;;;
;;; Pass 1 is the assembler representation: almost-final machine bytes grow
;;; upward from stagingStart while the few unresolved hole records grow downward
;;; from stagingLimit.  No source text survives here.

HOLE_VALUE_BYTE = $01
HOLE_VALUE_WORD = $02
HOLE_RELATIVE   = $03
HOLE_DIRECT     = $04
HOLE_DATA_BYTE  = $05

HOLE_FLAG_SHORT      = $01
HOLE_FLAG_RELAX_SAFE = $02
HOLE_FLAG_SYMBOL     = $04

HOLE_NEXT_LO    = 0
HOLE_NEXT_HI    = 1
HOLE_KIND       = 2
HOLE_FLAGS      = 3
HOLE_STAGE_LO   = 4
HOLE_STAGE_HI   = 5
HOLE_ADDRESS_LO = 6
HOLE_ADDRESS_HI = 7
HOLE_SYMBOL_LO  = 8
HOLE_SYMBOL_HI  = 9
HOLE_ADDEND_LO  = 10
HOLE_ADDEND_HI  = 11
HOLE_PREFIX     = 12
HOLE_EXTRA      = 13
HOLE_SIZE       = 14

;;; resetRepresentation
;;; Reset the caller-owned staging workspace.  Bytes and holes grow toward one
;;; another and ASSEMBLE_WORK_FULL is returned before they overlap.
resetRepresentation:
	lda stagingStart
	sta stagingPtr
	lda stagingStart+1
	sta stagingPtr+1
	lda stagingLimit
	sta holeFree
	lda stagingLimit+1
	sta holeFree+1
	lda #$00
	sta holeFirst
	sta holeFirst+1
	sta holeLast
	sta holeLast+1
	rts

;;; stageByte
;;; A is one final/conservative output byte.  Write it to staging and advance
;;; both the staged cursor and the conservative target PC assemblyPtr.
;;; Carry set on success, clear when staging has met the hole table.
stageByte:
	tax
	lda stagingPtr+1
	cmp holeFree+1
	bcc .room
	bne .full
	lda stagingPtr
	cmp holeFree
	bcc .room
.full:
	clc
	rts
.room:
	lda stagingPtr
	sta ZP_PTR0
	lda stagingPtr+1
	sta ZP_PTR0+1
	txa
	ldy #$00
	sta (ZP_PTR0),y
	inc stagingPtr
	bne .pc
	inc stagingPtr+1
.pc:
	inc assemblyPtr
	bne .ok
	inc assemblyPtr+1
.ok:
	sec
	rts

;;; appendHole
;;; Append one source-ordered fixed-size hole record.  Inputs are holeKind,
;;; holeStage, holeAddress, holeExtra, and captured* from captureValue.
;;; Carry set on success, clear with A=ASSEMBLE_WORK_FULL on collision.
appendHole:
	sec
	lda holeFree
	sbc #HOLE_SIZE
	sta holeNew
	lda holeFree+1
	sbc #$00
	sta holeNew+1

	lda holeNew+1
	cmp stagingPtr+1
	bcs .highEnough
	jmp .full
.highEnough:
	bne .room
	lda holeNew
	cmp stagingPtr
	bcs .room
	jmp .full
.room:
	lda #$00
	sta holeFlags
	lda capturedRelaxSafe
	beq .symbolFlag
	lda holeFlags
	ora #HOLE_FLAG_RELAX_SAFE
	sta holeFlags
.symbolFlag:
	lda capturedHasSymbol
	beq .flagsReady
	lda holeFlags
	ora #HOLE_FLAG_SYMBOL
	sta holeFlags
.flagsReady:

	lda holeNew
	sta ZP_PTR0
	lda holeNew+1
	sta ZP_PTR0+1
	ldy #HOLE_NEXT_LO
	lda #$00
	sta (ZP_PTR0),y
	iny
	sta (ZP_PTR0),y
	iny
	lda holeKind
	sta (ZP_PTR0),y
	iny
	lda holeFlags
	sta (ZP_PTR0),y
	iny
	lda holeStage
	sta (ZP_PTR0),y
	iny
	lda holeStage+1
	sta (ZP_PTR0),y
	iny
	lda holeAddress
	sta (ZP_PTR0),y
	iny
	lda holeAddress+1
	sta (ZP_PTR0),y
	iny
	lda capturedSymbol
	sta (ZP_PTR0),y
	iny
	lda capturedSymbol+1
	sta (ZP_PTR0),y
	iny
	lda capturedAddend
	sta (ZP_PTR0),y
	iny
	lda capturedAddend+1
	sta (ZP_PTR0),y
	iny
	lda capturedPrefix
	sta (ZP_PTR0),y
	iny
	lda holeExtra
	sta (ZP_PTR0),y

	lda holeLast
	ora holeLast+1
	beq .first
	lda holeLast
	sta ZP_PTR0
	lda holeLast+1
	sta ZP_PTR0+1
	ldy #HOLE_NEXT_LO
	lda holeNew
	sta (ZP_PTR0),y
	iny
	lda holeNew+1
	sta (ZP_PTR0),y
	jmp .linked
.first:
	lda holeNew
	sta holeFirst
	lda holeNew+1
	sta holeFirst+1
.linked:
	lda holeNew
	sta holeLast
	sta holeFree
	lda holeNew+1
	sta holeLast+1
	sta holeFree+1
	sec
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	clc
	rts

sealRepresentation:
	lda stagingPtr
	sta stagingEnd
	lda stagingPtr+1
	sta stagingEnd+1
	rts

;;; adjustAddress
;;; adjustInput is a conservative target address.  Subtract one for every
;;; earlier direct hole already marked short.  A label at the same address as an
;;; instruction is not moved by that instruction, hence the strict '<'.
;;;
;;; The routine uses holeScan for its internal walk but preserves the caller's
;;; hole cursor so it can safely be called while resolving a hole.
adjustAddress:
	lda holeScan
	pha
	lda holeScan+1
	pha
	lda adjustInput
	sta adjustResult
	lda adjustInput+1
	sta adjustResult+1
	lda holeFirst
	sta holeScan
	lda holeFirst+1
	sta holeScan+1
.next:
	lda holeScan
	ora holeScan+1
	beq .done
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_KIND
	lda (ZP_PTR0),y
	cmp #HOLE_DIRECT
	bne .advance
	iny
	lda (ZP_PTR0),y
	and #HOLE_FLAG_SHORT
	beq .advance
	ldy #HOLE_ADDRESS_HI
	lda (ZP_PTR0),y
	cmp adjustInput+1
	bcc .subtract
	bne .advance
	dey
	lda (ZP_PTR0),y
	cmp adjustInput
	bcs .advance
.subtract:
	lda adjustResult
	bne .decLow
	dec adjustResult+1
.decLow:
	dec adjustResult
.advance:
	jsr nextHole
	jmp .next
.done:
	pla
	sta holeScan+1
	pla
	sta holeScan
	rts

;;; resolveHoleValue
;;; Resolve the tiny stored recipe of holeScan against current symbol values.
;;; Carry clear means the referenced symbol is still undefined.
resolveHoleValue:
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_FLAGS
	lda (ZP_PTR0),y
	and #HOLE_FLAG_SYMBOL
	beq .literal
	ldy #HOLE_SYMBOL_LO
	lda (ZP_PTR0),y
	sta symbolEntry
	iny
	lda (ZP_PTR0),y
	sta symbolEntry+1
	jsr loadSymbolEntry
	lda symbolFlags
	and #SYMBOL_FLAG_DEFINED
	beq .undefined
	lda symbolValue
	sta resolvedValue
	lda symbolValue+1
	sta resolvedValue+1
	jmp .addend
.literal:
	lda #$00
	sta resolvedValue
	sta resolvedValue+1
.addend:
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_ADDEND_LO
	clc
	lda resolvedValue
	adc (ZP_PTR0),y
	sta resolvedValue
	iny
	lda resolvedValue+1
	adc (ZP_PTR0),y
	sta resolvedValue+1
	iny
	lda (ZP_PTR0),y
	beq .ok
	cmp #VALUE_PREFIX_LOW
	beq .low
	lda resolvedValue+1
	sta resolvedValue
.low:
	lda #$00
	sta resolvedValue+1
.ok:
	sec
	rts
.undefined:
	clc
	rts

;;; relaxLayout
;;; Recompute label addresses and monotonically mark conservative absolute
;;; instructions short until one complete memory walk makes no change.
relaxLayout:
.pass:
	jsr updateLabelValues
	lda #$00
	sta layoutChanged
	lda holeFirst
	sta holeScan
	lda holeFirst+1
	sta holeScan+1
.next:
	lda holeScan
	ora holeScan+1
	beq .passDone
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_KIND
	lda (ZP_PTR0),y
	cmp #HOLE_DIRECT
	bne .advance
	iny
	lda (ZP_PTR0),y
	and #HOLE_FLAG_SHORT
	bne .advance
	lda (ZP_PTR0),y
	and #HOLE_FLAG_RELAX_SAFE
	beq .advance
	jsr resolveHoleValue
	bcc .undefined
	lda resolvedValue+1
	bne .advance
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_FLAGS
	lda (ZP_PTR0),y
	ora #HOLE_FLAG_SHORT
	sta (ZP_PTR0),y
	lda #$01
	sta layoutChanged
.advance:
	jsr nextHole
	jmp .next
.passDone:
	lda layoutChanged
	bne .pass
	jsr updateLabelValues
	lda #ASSEMBLE_OK
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts

;;; resolveAllHoles
;;; Layout is now stable.  Patch only staging memory and validate every machine
;;; constraint before the final target region is touched.
resolveAllHoles:
	lda holeFirst
	sta holeScan
	lda holeFirst+1
	sta holeScan+1
.next:
	lda holeScan
	ora holeScan+1
	bne .haveHole
	jmp .ok
.haveHole:
	jsr resolveHoleValue
	bcs .resolved
	jmp .undefined
.resolved:
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_KIND
	lda (ZP_PTR0),y
	cmp #HOLE_VALUE_BYTE
	bne .notInstructionByte
	jmp .instructionByte
.notInstructionByte:
	cmp #HOLE_VALUE_WORD
	bne .notWord
	jmp .word
.notWord:
	cmp #HOLE_RELATIVE
	bne .notRelative
	jmp .relative
.notRelative:
	cmp #HOLE_DIRECT
	bne .notDirect
	jmp .direct
.notDirect:
	cmp #HOLE_DATA_BYTE
	bne .unknownKind
	jmp .dataByte
.unknownKind:
	jmp .badInstruction

.instructionByte:
	lda resolvedValue+1
	beq .instructionByteOk
	jmp .badInstruction
.instructionByteOk:
	jsr patchHoleByte
	jmp .advance
.dataByte:
	lda resolvedValue+1
	beq .dataByteOk
	jmp .badData
.dataByteOk:
	jsr patchHoleByte
	jmp .advance
.word:
	jsr patchHoleWord
	jmp .advance

.relative:
	ldy #HOLE_ADDRESS_LO
	lda (ZP_PTR0),y
	sta adjustInput
	iny
	lda (ZP_PTR0),y
	sta adjustInput+1
	jsr adjustAddress
	clc
	lda adjustResult
	adc #$02
	sta relativeBase
	lda adjustResult+1
	adc #$00
	sta relativeBase+1
	sec
	lda resolvedValue
	sbc relativeBase
	tax
	lda resolvedValue+1
	sbc relativeBase+1
	cpx #$80
	bcc .relativePositive
	cmp #$ff
	beq .relativeNegativeOk
	jmp .branchRange
.relativeNegativeOk:
	txa
	sta resolvedValue
	jsr patchHoleByte
	jmp .advance
.relativePositive:
	cmp #$00
	beq .relativePositiveOk
	jmp .branchRange
.relativePositiveOk:
	txa
	sta resolvedValue
	jsr patchHoleByte
	jmp .advance

.direct:
	ldy #HOLE_FLAGS
	lda (ZP_PTR0),y
	and #HOLE_FLAG_SHORT
	beq .directLong
	lda resolvedValue+1
	beq .directShortOk
	jmp .badInstruction
.directShortOk:
	ldy #HOLE_EXTRA
	lda (ZP_PTR0),y
	tax				; short opcode
	ldy #HOLE_STAGE_LO
	lda (ZP_PTR0),y
	sta patchPtr
	iny
	lda (ZP_PTR0),y
	sta patchPtr+1
	lda patchPtr
	sta ZP_PTR0
	lda patchPtr+1
	sta ZP_PTR0+1
	ldy #$00
	txa
	sta (ZP_PTR0),y
	iny
	lda resolvedValue
	sta (ZP_PTR0),y
	jmp .advance
.directLong:
	ldy #HOLE_STAGE_LO
	lda (ZP_PTR0),y
	sta patchPtr
	iny
	lda (ZP_PTR0),y
	sta patchPtr+1
	lda patchPtr
	sta ZP_PTR0
	lda patchPtr+1
	sta ZP_PTR0+1
	ldy #$01			; byte zero is the already-staged long opcode
	lda resolvedValue
	sta (ZP_PTR0),y
	iny
	lda resolvedValue+1
	sta (ZP_PTR0),y
	jmp .advance

.advance:
	jsr nextHole
	jmp .next
.ok:
	lda #ASSEMBLE_OK
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts
.badInstruction:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.badData:
	lda #ASSEMBLE_BAD_DATA
	rts
.branchRange:
	lda #ASSEMBLE_EMIT_ERROR
	rts

patchHoleByte:
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_STAGE_LO
	lda (ZP_PTR0),y
	sta patchPtr
	iny
	lda (ZP_PTR0),y
	sta patchPtr+1
	lda patchPtr
	sta ZP_PTR0
	lda patchPtr+1
	sta ZP_PTR0+1
	ldy #$00
	lda resolvedValue
	sta (ZP_PTR0),y
	rts

patchHoleWord:
	jsr patchHoleByte
	lda patchPtr
	sta ZP_PTR0
	lda patchPtr+1
	sta ZP_PTR0+1
	ldy #$01
	lda resolvedValue+1
	sta (ZP_PTR0),y
	rts

;;; copyRepresentation
;;; Commit the validated staged image to assemblyStart.  Short direct holes skip
;;; the one conservative excess byte; everything else copies literally.
copyRepresentation:
	lda stagingStart
	sta copyStage
	lda stagingStart+1
	sta copyStage+1
	lda holeFirst
	sta copyHole
	lda holeFirst+1
	sta copyHole+1
	lda assemblyStart
	sta assemblyPtr
	lda assemblyStart+1
	sta assemblyPtr+1
.loop:
	lda copyStage
	cmp stagingEnd
	bne .haveByte
	lda copyStage+1
	cmp stagingEnd+1
	bne .haveByte
	jmp .done
.haveByte:
	lda copyHole
	ora copyHole+1
	beq .normal
	lda copyHole
	sta ZP_PTR0
	lda copyHole+1
	sta ZP_PTR0+1
	ldy #HOLE_STAGE_LO
	lda (ZP_PTR0),y
	cmp copyStage
	bne .normal
	iny
	lda (ZP_PTR0),y
	cmp copyStage+1
	bne .normal
	ldy #HOLE_KIND
	lda (ZP_PTR0),y
	cmp #HOLE_DIRECT
	bne .consumeHole
	iny
	lda (ZP_PTR0),y
	and #HOLE_FLAG_SHORT
	beq .consumeHole

	;; Short direct form: copy opcode+operand, then skip the conservative high byte.
	lda copyStage
	sta ZP_PTR0
	lda copyStage+1
	sta ZP_PTR0+1
	lda assemblyPtr
	sta ZP_PTR1
	lda assemblyPtr+1
	sta ZP_PTR1+1
	ldy #$00
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	iny
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	lda #$03
	jsr advanceCopyStage
	lda #$02
	jsr advanceFinalPtr
	jsr consumeCopyHole
	jmp .loop

.consumeHole:
	jsr consumeCopyHole
.normal:
	lda copyStage
	sta ZP_PTR0
	lda copyStage+1
	sta ZP_PTR0+1
	lda assemblyPtr
	sta ZP_PTR1
	lda assemblyPtr+1
	sta ZP_PTR1+1
	ldy #$00
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	lda #$01
	jsr advanceCopyStage
	lda #$01
	jsr advanceFinalPtr
	jmp .loop
.done:
	lda #ASSEMBLE_OK
	rts

consumeCopyHole:
	lda copyHole
	sta ZP_PTR0
	lda copyHole+1
	sta ZP_PTR0+1
	ldy #HOLE_NEXT_LO
	lda (ZP_PTR0),y
	sta copyHole
	iny
	lda (ZP_PTR0),y
	sta copyHole+1
	rts

;;; nextHole
;;; Advance holeScan through the source-ordered linked list.
nextHole:
	lda holeScan
	sta ZP_PTR0
	lda holeScan+1
	sta ZP_PTR0+1
	ldy #HOLE_NEXT_LO
	lda (ZP_PTR0),y
	tax
	iny
	lda (ZP_PTR0),y
	sta holeScan+1
	stx holeScan
	rts

advanceCopyStage:
	clc
	adc copyStage
	sta copyStage
	bcc .done
	inc copyStage+1
.done:
	rts

advanceFinalPtr:
	clc
	adc assemblyPtr
	sta assemblyPtr
	bcc .done
	inc assemblyPtr+1
.done:
	rts

stagingStart:	word 0
stagingLimit:	word 0
stagingPtr:	word 0
stagingEnd:	word 0
holeFree:	word 0
holeFirst:	word 0
holeLast:	word 0

holeKind:	byte 0
holeFlags:	byte 0
holeStage:	word 0
holeAddress:	word 0
holeExtra:	byte 0
holeNew:	word 0
holeScan:	word 0

adjustInput:	word 0
adjustResult:	word 0
resolvedValue:	word 0
relativeBase:	word 0
patchPtr:	word 0
layoutChanged:	byte 0

copyStage:	word 0
copyHole:	word 0
