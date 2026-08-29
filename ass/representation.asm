;;; representation.asm
;;;
;;; Assembly stages final-size machine bytes. Ordinary unresolved 16-bit label
;;; references use their own two operand bytes as a chain and need no record
;;; here. The only side records are exceptional forward fixups whose output byte
;;; cannot also hold a 16-bit chain pointer: byte values, word expressions, and
;;; relative branches.
;;;
;;; Fixups are fixed-size and contiguous, growing downward from stagingLimit.
;;; Resolved fixups stay in place but have kind FIXUP_NONE. There is deliberately
;;; no allocator or free list: these records are small and uncommon compared with
;;; the staged machine image.

FIXUP_NONE             = $00
FIXUP_INSTRUCTION_BYTE = $01
FIXUP_WORD             = $02
FIXUP_RELATIVE         = $03
FIXUP_DATA_BYTE        = $04

FIXUP_KIND       = 0
FIXUP_STAGE_LO   = 1
FIXUP_STAGE_HI   = 2
FIXUP_SYMBOL_LO  = 3
FIXUP_SYMBOL_HI  = 4
FIXUP_ADDEND_LO  = 5
FIXUP_ADDEND_HI  = 6
FIXUP_PREFIX     = 7
FIXUP_SIZE       = 8

;;; resetRepresentation
;;; Reset the caller-owned staging workspace. Bytes and fixups grow toward one
;;; another and ASSEMBLE_WORK_FULL is returned before they overlap.
resetRepresentation:
	lda stagingStart
	sta stagingPtr
	lda stagingStart+1
	sta stagingPtr+1
	lda stagingLimit
	sta fixupFree
	lda stagingLimit+1
	sta fixupFree+1
	rts

;;; stageByte
;;; A is one final output byte. Write it to staging and advance both the staging
;;; cursor and the final target PC assemblyPtr.
;;; Carry set on success, clear when staging has met the fixup records.
stageByte:
	tax
	lda stagingPtr+1
	cmp fixupFree+1
	bcc .room
	bne .full
	lda stagingPtr
	cmp fixupFree
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

;;; appendFixup
;;; Allocate one exceptional forward fixup. Inputs are fixupKind, fixupStage,
;;; capturedSymbol, capturedAddend, and capturedPrefix.
;;; Carry set on success, clear with A=ASSEMBLE_WORK_FULL on collision.
appendFixup:
	sec
	lda fixupFree
	sbc #FIXUP_SIZE
	sta ZP_PTR0
	lda fixupFree+1
	sbc #$00
	sta ZP_PTR0+1

	lda ZP_PTR0+1
	cmp stagingPtr+1
	bcc .full
	bne .room
	lda ZP_PTR0
	cmp stagingPtr
	bcc .full
.room:
	ldy #FIXUP_KIND
	lda fixupKind
	sta (ZP_PTR0),y
	iny
	lda fixupStage
	sta (ZP_PTR0),y
	iny
	lda fixupStage+1
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

	lda ZP_PTR0
	sta fixupFree
	lda ZP_PTR0+1
	sta fixupFree+1
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

;;; firstFixup / nextFixup
;;; Fixups were allocated downward, so source order is a simple downward walk.
;;; A zero fixupScan means there are no more records.
firstFixup:
	lda stagingLimit
	sta fixupScan
	lda stagingLimit+1
	sta fixupScan+1
	jmp nextFixup

nextFixup:
	sec
	lda fixupScan
	sbc #FIXUP_SIZE
	sta fixupScan
	lda fixupScan+1
	sbc #$00
	sta fixupScan+1

	lda fixupScan+1
	cmp fixupFree+1
	bcc .done
	bne .have
	lda fixupScan
	cmp fixupFree
	bcc .done
.have:
	rts
.done:
	lda #$00
	sta fixupScan
	sta fixupScan+1
	rts

;;; resolveFixupValue
;;; The label identified by symbolEntry has just been defined and symbolValue is
;;; therefore final. Apply this fixup's small addend and optional byte selector.
resolveFixupValue:
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_ADDEND_LO
	clc
	lda symbolValue
	adc (ZP_PTR0),y
	sta resolvedValue
	iny
	lda symbolValue+1
	adc (ZP_PTR0),y
	sta resolvedValue+1
	iny
	lda (ZP_PTR0),y
	beq .done
	cmp #VALUE_PREFIX_LOW
	beq .low
	lda resolvedValue+1
	sta resolvedValue
.low:
	lda #$00
	sta resolvedValue+1
.done:
	rts

;;; resolveSymbolFixups
;;; A label has just been defined. Walk the small exceptional-fixup table and
;;; patch every record waiting for this symbol immediately. Successful records
;;; are marked FIXUP_NONE; their storage is not reclaimed.
;;; Returns ASSEMBLE_* in A.
resolveSymbolFixups:
	jsr firstFixup
.next:
	lda fixupScan
	ora fixupScan+1
	beq .ok
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_KIND
	lda (ZP_PTR0),y
	beq .advance
	ldy #FIXUP_SYMBOL_LO
	lda (ZP_PTR0),y
	cmp symbolEntry
	bne .advance
	iny
	lda (ZP_PTR0),y
	cmp symbolEntry+1
	bne .advance

	jsr resolveFixupValue
	jsr patchCurrentFixup
	cmp #ASSEMBLE_OK
	bne .done
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_KIND
	lda #FIXUP_NONE
	sta (ZP_PTR0),y
.advance:
	jsr nextFixup
	jmp .next
.ok:
	lda #ASSEMBLE_OK
.done:
	rts

;;; patchCurrentFixup
;;; resolvedValue contains the final value for fixupScan.
patchCurrentFixup:
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_KIND
	lda (ZP_PTR0),y
	cmp #FIXUP_INSTRUCTION_BYTE
	beq .instructionByte
	cmp #FIXUP_WORD
	beq .word
	cmp #FIXUP_RELATIVE
	beq .relative
	cmp #FIXUP_DATA_BYTE
	beq .dataByte
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts

.instructionByte:
	lda resolvedValue+1
	beq .patchByte
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.dataByte:
	lda resolvedValue+1
	beq .patchByte
	lda #ASSEMBLE_BAD_DATA
	rts
.patchByte:
	jsr patchFixupByte
	lda #ASSEMBLE_OK
	rts

.word:
	jsr patchFixupWord
	lda #ASSEMBLE_OK
	rts

.relative:
	;; fixupStage points at the branch operand byte. With fixed instruction widths,
	;; its target address is assemblyStart + (fixupStage-stagingStart); the branch
	;; base is the following byte.
	ldy #FIXUP_STAGE_LO
	lda (ZP_PTR0),y
	sta fixupStage
	iny
	lda (ZP_PTR0),y
	sta fixupStage+1
	sec
	lda fixupStage
	sbc stagingStart
	sta relativeBase
	lda fixupStage+1
	sbc stagingStart+1
	sta relativeBase+1
	clc
	lda relativeBase
	adc assemblyStart
	sta relativeBase
	lda relativeBase+1
	adc assemblyStart+1
	sta relativeBase+1
	inc relativeBase
	bne .haveBase
	inc relativeBase+1
.haveBase:
	sec
	lda resolvedValue
	sbc relativeBase
	tax
	lda resolvedValue+1
	sbc relativeBase+1
	cpx #$80
	bcc .positive
	cmp #$ff
	bne .branchRange
	txa
	sta resolvedValue
	jsr patchFixupByte
	lda #ASSEMBLE_OK
	rts
.positive:
	cmp #$00
	bne .branchRange
	txa
	sta resolvedValue
	jsr patchFixupByte
	lda #ASSEMBLE_OK
	rts
.branchRange:
	lda #ASSEMBLE_EMIT_ERROR
	rts

patchFixupByte:
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_STAGE_LO
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

patchFixupWord:
	jsr patchFixupByte
	lda patchPtr
	sta ZP_PTR0
	lda patchPtr+1
	sta ZP_PTR0+1
	ldy #$01
	lda resolvedValue+1
	sta (ZP_PTR0),y
	rts

;;; allFixupsResolved
;;; Once all labels are defined every exceptional forward fixup should already
;;; have been patched by resolveSymbolFixups. Carry set means that invariant holds.
allFixupsResolved:
	jsr firstFixup
.next:
	lda fixupScan
	ora fixupScan+1
	beq .ok
	lda fixupScan
	sta ZP_PTR0
	lda fixupScan+1
	sta ZP_PTR0+1
	ldy #FIXUP_KIND
	lda (ZP_PTR0),y
	bne .bad
	jsr nextFixup
	jmp .next
.ok:
	sec
	rts
.bad:
	clc
	rts

;;; copyRepresentation
;;; The staged image already has final widths and final bytes. Commit it literally
;;; to assemblyStart only after all symbols and fixups have validated.
copyRepresentation:
	lda stagingStart
	sta copyStage
	lda stagingStart+1
	sta copyStage+1
	lda assemblyStart
	sta assemblyPtr
	lda assemblyStart+1
	sta assemblyPtr+1
.loop:
	lda copyStage
	cmp stagingEnd
	bne .copy
	lda copyStage+1
	cmp stagingEnd+1
	beq .done
.copy:
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
	inc copyStage
	bne .final
	inc copyStage+1
.final:
	inc assemblyPtr
	bne .loop
	inc assemblyPtr+1
	jmp .loop
.done:
	lda #ASSEMBLE_OK
	rts

stagingStart:	word 0
stagingLimit:	word 0
stagingPtr:	word 0
stagingEnd:	word 0
fixupFree:	word 0

fixupKind:	byte 0
fixupStage:	word 0
fixupScan:	word 0

resolvedValue:	word 0
relativeBase:	word 0
patchPtr:	word 0
copyStage:	word 0
