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
;;; ZP_PTR1 is the assembler source cursor. Borrow it as the argument base while
;;; handling this one statement, then restore it before returning.
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
	tax				; keep status while restoring source cursor
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	txa
	rts

;;; assembleDataList
;;; A = bytes per item (1 for byte, 2 for word).
;;; Walk the argument directly with a one-byte offset. nextDataItem returns the
;;; current item as ZP_PTR0/X for parseValue and leaves dataOffset at the next
;;; item (or at the end of the argument).
assembleDataList:
	sta dataWidth
	lda #$00
	sta dataOffset

.next:
	jsr nextDataItem
	bcc .bad
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
	lda dataOffset
	cmp statementArgumentLength
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
;;; Return the next trimmed item as ZP_PTR0/X. The argument base is ZP_PTR1.
;;; Empty items and trailing commas return carry clear.
nextDataItem:
	ldy dataOffset
	jsr skipDataSpaces
	cpy statementArgumentLength
	beq .bad
	sty dataOffset			; current item start
	ldx #$00			; trimmed item length

.scan:
	cpy statementArgumentLength
	beq .last
	lda (ZP_PTR1),y
	cmp #','
	beq .comma
	cmp #' '
	beq .advance
	cmp #$09
	beq .advance

	;; Length extends through the most recent non-whitespace byte.
	tya
	sec
	sbc dataOffset
	tax
	inx

.advance:
	iny
	jmp .scan

.comma:
	cpx #$00
	beq .bad
	jsr setDataItemPointer
	iny				; consume comma
	jsr skipDataSpaces
	cpy statementArgumentLength
	beq .bad			; trailing comma
	sty dataOffset			; next item start
	sec
	rts

.last:
	cpx #$00
	beq .bad
	jsr setDataItemPointer
	sty dataOffset			; end of argument
	sec
	rts
.bad:
	clc
	rts

;;; skipDataSpaces
;;; Y is an offset into the argument at ZP_PTR1. Skip spaces/tabs in place.
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

;;; setDataItemPointer
;;; dataOffset is the item's start and X is its length. Point ZP_PTR0 at it.
;;; X and Y are preserved.
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
;;; ZP_PTR1 points at the string argument. Like vasm oldstyle, string emits the
;;; literal bytes followed by one NUL byte; nanoc already relies on this for
;;; source lines. There is deliberately no escape language yet.
assembleString:
	lda statementArgumentLength
	cmp #$02
	bcs .hasArgument
	jmp .bad
.hasArgument:
	ldy #$00
	lda (ZP_PTR1),y
	cmp #'"'
	beq .scan
	jmp .bad

.scan:
	iny
	cpy statementArgumentLength
	beq .bad
	lda (ZP_PTR1),y
	cmp #'"'
	bne .scan

	;; The first closing quote must also be the final argument byte. Its offset
	;; is exactly the output size: literal bytes plus the NUL terminator.
	sty dataOffset
	iny
	cpy statementArgumentLength
	bne .bad

	lda assemblyPass
	cmp #PASS_LAYOUT
	bne .emit
	lda dataOffset
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts

.emit:
	lda #$01			; first literal byte, after the opening quote
	sta dataOffset
.emitLoop:
	ldy dataOffset
	lda (ZP_PTR1),y
	cmp #'"'
	beq .terminator
	inc dataOffset
	jsr emitAssemblyByte
	jmp .emitLoop

.terminator:
	lda #$00
	jsr emitAssemblyByte
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_DATA
	rts

;;; emitAssemblyByte
;;; A is written at assemblyPtr, then assemblyPtr advances by one.
;;; ZP_PTR0, A, X and Y are clobbered.
emitAssemblyByte:
	tax
	lda assemblyPtr
	sta ZP_PTR0
	lda assemblyPtr+1
	sta ZP_PTR0+1
	txa
	ldy #$00
	sta (ZP_PTR0),y
	inc assemblyPtr
	bne .done
	inc assemblyPtr+1
.done:
	rts

;;; Two bytes of explicit state are enough for one data declaration.
dataWidth:	byte 0
dataOffset:	byte 0
