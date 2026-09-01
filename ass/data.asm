;;; data.asm
;;;
;;; The three data declarations used by ass itself:
;;;
;;;     byte value [, value ...]
;;;     word value [, value ...]
;;;     string "literal"
;;;
;;; Fixed values become staged bytes immediately. A plain unresolved `word label`
;;; uses its own two staged bytes as part of the label's reference chain. Only
;;; one-byte values and word expressions need a separate forward fixup.

DATA_NONE   = $00
DATA_BYTE   = $01
DATA_WORD   = $02
DATA_STRING = $03

;;; dataStatementKind
;;; Return DATA_* in A for the bare statement names byte, word, and string.
dataStatementKind:
	lda statementNameLength
	cmp #$04
	beq .four
	cmp #$06
	beq .string
	lda #DATA_NONE
	rts
.four:
	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'b'
	beq .byte
	cmp #'w'
	beq .word
	lda #DATA_NONE
	rts
.byte:
	iny
	lda (ZP_PTR0),y
	cmp #'y'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'t'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'e'
	bne .none
	lda #DATA_BYTE
	rts
.word:
	iny
	lda (ZP_PTR0),y
	cmp #'o'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'r'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'d'
	bne .none
	lda #DATA_WORD
	rts
.string:
	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'s'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'t'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'r'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'i'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'n'
	bne .none
	iny
	lda (ZP_PTR0),y
	cmp #'g'
	bne .none
	lda #DATA_STRING
	rts
.none:
	lda #DATA_NONE
	rts

;;; assembleData
;;; A = DATA_*. ZP_PTR1 is preserved because it is normally the source cursor.
assembleData:
	tax
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha
	lda statementArgument
	sta ZP_PTR1
	lda statementArgument+1
	sta ZP_PTR1+1
	txa
	cmp #DATA_BYTE
	beq .byte
	cmp #DATA_WORD
	beq .word
	jsr assembleString
	jmp .restore
.byte:
	lda #$01
	jsr assembleDataList
	jmp .restore
.word:
	lda #$02
	jsr assembleDataList
.restore:
	tax
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	txa
	rts

;;; assembleDataList
;;; A = fixed output width per item; ZP_PTR1 = complete argument base.
assembleDataList:
	sta dataWidth
	lda #$00
	sta dataOffset
.next:
	jsr nextDataItem
	bcs .itemReady
	jmp .bad
.itemReady:
	jsr parseValue
	cmp #VALUE_OK
	beq .fixed
	cmp #VALUE_UNRESOLVED
	beq .deferred
	cmp #VALUE_SYMBOL_FULL
	bne .notSymbolFull
	jmp .symbolFull
.notSymbolFull:
	cmp #VALUE_SCOPE_ERROR
	bne .valueBad
	jmp .scope
.valueBad:
	jmp .bad

.fixed:
	lda dataWidth
	cmp #$01
	bne .fixedWord
	lda valueResult+1
	beq .fixedByteOk
	jmp .bad
.fixedByteOk:
	lda valueResult
	jsr stageByte
	bcc .workFullNear
	jmp .itemDone
.fixedWord:
	lda valueResult
	jsr stageByte
	bcc .workFullNear
	lda valueResult+1
	jsr stageByte
	bcc .workFullNear
	jmp .itemDone

.deferred:
	lda dataWidth
	cmp #$02
	bne .fixup
	jsr isPlainLabelValue
	bcc .fixup
	jsr stagePlainWordReference
	bcc .workFullNear
	jmp .itemDone

.workFullNear:
	jmp .workFull

.fixup:
	lda stagingPtr
	sta fixupStage
	lda stagingPtr+1
	sta fixupStage+1
	lda dataWidth
	cmp #$01
	beq .byteFixup
	lda #FIXUP_WORD
	sta fixupKind
	lda #$00
	jsr stageByte
	bcc .workFull
	lda #$00
	jsr stageByte
	bcc .workFull
	jsr appendFixup
	bcc .workFull
	jmp .itemDone
.byteFixup:
	lda #FIXUP_DATA_BYTE
	sta fixupKind
	lda #$00
	jsr stageByte
	bcc .workFull
	jsr appendFixup
	bcc .workFull

.itemDone:
	lda dataOffset
	cmp statementArgumentLength
	beq .done
	jmp .next
.done:
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_DATA
	rts
.symbolFull:
	lda #ASSEMBLE_SYMBOL_FULL
	rts
.scope:
	lda #ASSEMBLE_SCOPE_ERROR
	rts
.workFull:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; nextDataItem
;;; Return one trimmed comma-separated item as ZP_PTR0/X. Character atoms are
;;; exactly three bytes in the value grammar, so their middle byte is data even
;;; when it is a comma or whitespace.
nextDataItem:
	ldy dataOffset
	jsr skipDataSpaces
	cpy statementArgumentLength
	beq .bad
	sty dataOffset
	ldx #$00
.scan:
	cpy statementArgumentLength
	beq .last
	lda (ZP_PTR1),y
	cmp #39				; apostrophe starts the existing 'c' atom
	beq .character
	cmp #','
	beq .comma
	cmp #' '
	beq .advance
	cmp #$09
	beq .advance
	tya
	sec
	sbc dataOffset
	tax
	inx
.advance:
	iny
	jmp .scan
.character:
	;;; Skip opening quote, the one character byte, and the closing quote as one
	;;; indivisible item. parseValue performs the actual quote validation later.
	iny
	cpy statementArgumentLength
	beq .bad
	iny
	cpy statementArgumentLength
	beq .bad
	iny
	tya
	sec
	sbc dataOffset
	tax
	jmp .scan
.comma:
	cpx #$00
	beq .bad
	jsr setDataItemPointer
	iny
	jsr skipDataSpaces
	cpy statementArgumentLength
	beq .bad
	sty dataOffset
	sec
	rts
.last:
	cpx #$00
	beq .bad
	jsr setDataItemPointer
	sty dataOffset
	sec
	rts
.bad:
	clc
	rts

skipDataSpaces:
.loop:
	cpy statementArgumentLength
	beq .done
	lda (ZP_PTR1),y
	cmp #' '
	beq .skip
	cmp #$09
	bne .done
.skip:
	iny
	jmp .loop
.done:
	rts

setDataItemPointer:
	clc
	lda ZP_PTR1
	adc dataOffset
	sta ZP_PTR0
	lda ZP_PTR1+1
	adc #$00
	sta ZP_PTR0+1
	rts

;;; assembleString
;;; Emit literal bytes plus one NUL into staging. stageByte clobbers Y, so the
;;; source offset lives explicitly in dataOffset rather than in a register.
assembleString:
	lda statementArgumentLength
	cmp #$02
	bcc .bad
	ldy #$00
	lda (ZP_PTR1),y
	cmp #'"'
	bne .bad
	lda #$01
	sta dataOffset
.loop:
	ldy dataOffset
	cpy statementArgumentLength
	beq .bad
	lda (ZP_PTR1),y
	cmp #'"'
	beq .close
	inc dataOffset
	jsr stageByte
	bcc .workFull
	jmp .loop
.close:
	iny
	cpy statementArgumentLength
	bne .bad
	lda #$00
	jsr stageByte
	bcc .workFull
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_DATA
	rts
.workFull:
	lda #ASSEMBLE_WORK_FULL
	rts

dataWidth:	byte 0
dataOffset:	byte 0
