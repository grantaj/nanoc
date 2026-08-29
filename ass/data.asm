;;; data.asm
;;;
;;; The three data declarations used by nanoc itself:
;;;
;;;     byte value [, value ...]
;;;     word value [, value ...]
;;;     string "literal"
;;;
;;; Pass 1 only advances assemblyPtr. Pass 2 writes directly to assemblyPtr.
;;; There is no stored data list or separate output representation.

DATA_NONE   = $00
DATA_BYTE   = $01
DATA_WORD   = $02
DATA_STRING = $03

;;; dataStatementKind
;;; Return DATA_* for the bare statement names byte, word, and string.
;;; ZP_PTR0, A and Y are clobbered.
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
;;; A contains DATA_BYTE, DATA_WORD, or DATA_STRING.
assembleData:
	cmp #DATA_BYTE
	beq .byte
	cmp #DATA_WORD
	beq .word
	jmp assembleString
.byte:
	lda #$01
	sta dataWidth
	jmp assembleDataList
.word:
	lda #$02
	sta dataWidth
	jmp assembleDataList

;;; assembleDataList
;;; Walk a comma-separated byte/word list directly in the statement argument.
assembleDataList:
	lda statementArgument
	sta dataCursor
	lda statementArgument+1
	sta dataCursor+1
	lda statementArgumentLength
	sta dataLeft

.next:
	jsr nextDataItem
	bcc .bad
	sta dataMore

	lda dataItem
	sta ZP_PTR0
	lda dataItem+1
	sta ZP_PTR0+1
	ldx dataItemLength
	jsr parseValue
	cmp #VALUE_BAD
	beq .bad
	cmp #VALUE_UNRESOLVED
	beq .unresolved

	;; A byte declaration must really fit in one byte.
	lda dataWidth
	cmp #$01
	bne .resolved
	lda valueResult+1
	bne .bad

.resolved:
	lda assemblyPass
	cmp #PASS_LAYOUT
	beq .count

	lda valueResult
	jsr emitAssemblyByte
	lda dataWidth
	cmp #$01
	beq .itemDone
	lda valueResult+1
	jsr emitAssemblyByte
	jmp .itemDone

.unresolved:
	lda assemblyPass
	cmp #PASS_LAYOUT
	bne .undefined

.count:
	lda dataWidth
	jsr advanceAssemblyPtr

.itemDone:
	lda dataMore
	bne .next
	lda #ASSEMBLE_OK
	rts

.bad:
	lda #ASSEMBLE_BAD_DATA
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts

;;; nextDataItem
;;; Return the next trimmed list item in dataItem/dataItemLength.
;;; Carry set means an item was found. A=1 means another item follows; A=0 means
;;; this was the last item. Empty items and trailing commas return carry clear.
nextDataItem:
	jsr skipDataSpaces
	lda dataLeft
	beq .bad

	lda dataCursor
	sta dataItem
	lda dataCursor+1
	sta dataItem+1
	lda #$00
	sta dataItemLength
	ldx #$00

.scan:
	lda dataLeft
	beq .last
	lda dataCursor
	sta ZP_PTR0
	lda dataCursor+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #','
	beq .comma
	cmp #' '
	beq .consume
	cmp #$09
	beq .consume

	;; Remember the extent through the latest non-whitespace byte. This trims
	;; spaces before a comma without copying or rescanning the item.
	txa
	clc
	adc #$01
	sta dataItemLength

.consume:
	inx
	jsr advanceDataCursor
	jmp .scan

.comma:
	lda dataItemLength
	beq .bad
	jsr advanceDataCursor		; consume comma
	jsr skipDataSpaces
	lda dataLeft
	beq .bad			; trailing comma
	lda #$01
	sec
	rts

.last:
	lda dataItemLength
	beq .bad
	lda #$00
	sec
	rts
.bad:
	clc
	rts

;;; skipDataSpaces
;;; Skip spaces/tabs at dataCursor.
skipDataSpaces:
.loop:
	lda dataLeft
	beq .done
	lda dataCursor
	sta ZP_PTR0
	lda dataCursor+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #' '
	beq .skip
	cmp #$09
	bne .done
.skip:
	jsr advanceDataCursor
	jmp .loop
.done:
	rts

;;; advanceDataCursor
;;; Advance the ordinary-memory data cursor by one byte.
advanceDataCursor:
	inc dataCursor
	bne .noCarry
	inc dataCursor+1
.noCarry:
	dec dataLeft
	rts

;;; assembleString
;;; Accept one quoted literal and emit exactly the bytes between its quotes.
;;; Quotes inside the literal are not supported because there is no escape
;;; language yet.
assembleString:
	lda statementArgumentLength
	cmp #$02
	bcc .bad

	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'"'
	bne .bad

	;; Scan to the closing quote. It must be the final argument byte.
	clc
	lda statementArgument
	adc #$01
	sta dataCursor
	lda statementArgument+1
	adc #$00
	sta dataCursor+1
	lda statementArgumentLength
	sec
	sbc #$01
	sta dataLeft
	lda #$00
	sta dataItemLength		; literal length

.scanString:
	lda dataLeft
	beq .bad
	lda dataCursor
	sta ZP_PTR0
	lda dataCursor+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'"'
	beq .closingQuote
	inc dataItemLength
	jsr advanceDataCursor
	jmp .scanString

.closingQuote:
	lda dataLeft
	cmp #$01
	bne .bad

	lda assemblyPass
	cmp #PASS_LAYOUT
	bne .emit
	lda dataItemLength
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts

.emit:
	clc
	lda statementArgument
	adc #$01
	sta dataCursor
	lda statementArgument+1
	adc #$00
	sta dataCursor+1
	lda dataItemLength
	sta dataLeft

.emitLoop:
	lda dataLeft
	beq .ok
	lda dataCursor
	sta ZP_PTR0
	lda dataCursor+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	jsr emitAssemblyByte
	jsr advanceDataCursor
	jmp .emitLoop

.ok:
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_DATA
	rts

;;; emitAssemblyByte
;;; A is written at assemblyPtr, then assemblyPtr advances by one.
;;; ZP_PTR0 and Y are clobbered.
emitAssemblyByte:
	pha
	lda assemblyPtr
	sta ZP_PTR0
	lda assemblyPtr+1
	sta ZP_PTR0+1
	pla
	ldy #$00
	sta (ZP_PTR0),y
	inc assemblyPtr
	bne .done
	inc assemblyPtr+1
.done:
	rts

;;; Small explicit state used only while walking one data declaration.
dataWidth:		byte 0
dataMore:		byte 0
dataCursor:		word 0
dataLeft:		byte 0
dataItem:		word 0
dataItemLength:	byte 0
