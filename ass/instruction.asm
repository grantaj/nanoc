;;; instruction.asm
;;;
;;; Parse a STATEMENT_INSTRUCTION directly from the zero-copy views produced by
;;; nextStatement. The disassembler tables remain the one description of the
;;; 6502 instruction set.
;;;
;;; parseInstruction output:
;;;   A                       status (INSTRUCTION_*)
;;;   instructionMnemonic     mnemonic-table index
;;;   instructionMode         MODE_* or MODE_DEFERRED
;;;   instructionOpcode       opcode, or $ff while mode is deferred
;;;   instructionOperandKind  OPERAND_NONE / NUMBER / SYMBOL
;;;   instructionOperandValue 16-bit numeric value
;;;   instructionSymbol       zero-copy pointer/length for a symbol
;;;   instructionIndex        INDEX_* only when MODE_DEFERRED needs it
;;;
;;; ZP_PTR1 and the source buffer are preserved. A, X, Y, ZP_PTR0 and flags
;;; are clobbered.

	include "../dis/mode_ids.inc"

INSTRUCTION_OK           = $00
INSTRUCTION_BAD_MNEMONIC = $01
INSTRUCTION_BAD_OPERAND  = $02
INSTRUCTION_BAD_MODE     = $03

OPERAND_NONE   = $00
OPERAND_NUMBER = $01
OPERAND_SYMBOL = $02

INDEX_NONE = $00
INDEX_X    = $01
INDEX_Y    = $02

MODE_DEFERRED = $ff
MNEMONIC_COUNT = $38		; $38 is the ??? sentinel, not a source mnemonic

;;; parseInstruction
;;;
;;; statementName/statementArgument contain the views returned by nextStatement.
;;; Returns INSTRUCTION_* in A and fills the instruction semantic state above.
;;; ZP_PTR1 and the source buffer are preserved. A, X, Y, ZP_PTR0 and flags
;;; are clobbered.
parseInstruction:
	jsr clearInstruction

	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldx statementNameLength
	jsr findMnemonic
	bcs .mnemonicOk
	lda #INSTRUCTION_BAD_MNEMONIC
	rts
.mnemonicOk:
	sta instructionMnemonic

	lda statementArgumentLength
	bne .hasOperand
	lda #MODE_IMPLIED
	jmp finishKnownMode

.hasOperand:
	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldx statementArgumentLength
	jmp parseOperand

;;; clearInstruction
;;;
;;; Reset all semantic outputs before parsing a new instruction.
;;; A is clobbered. X and Y are preserved.
clearInstruction:
	lda #$00
	sta instructionMnemonic
	sta instructionOperandKind
	sta instructionOperandValue
	sta instructionOperandValue+1
	sta instructionSymbol
	sta instructionSymbol+1
	sta instructionSymbolLength
	sta instructionIndex
	sta operandIndex
	lda #MODE_DEFERRED
	sta instructionMode
	sta instructionOpcode
	rts

;;; parseOperand
;;;
;;; ZP_PTR0/X identify the complete operand text. Dispatch by the punctuation
;;; that distinguishes the 6502 addressing forms.
;;; Returns INSTRUCTION_* in A. A, X, Y and flags are clobbered; ZP_PTR0 may
;;; advance when leading punctuation is removed.
parseOperand:
	cpx #$01
	bne .notAccumulator
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'A'
	bne parseDirectOperand
	lda #MODE_ACCUMULATOR
	jmp finishKnownMode

.notAccumulator:
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'#'
	beq parseImmediateOperand
	cmp #'('
	beq parseIndirectOperand
	jmp parseDirectOperand

;;; parseImmediateOperand
;;;
;;; ZP_PTR0/X identify an operand beginning with '#'.
parseImmediateOperand:
	jsr advanceOperandStart
	jsr parseByteOperandCore
	bcs .ok
	jmp badOperand
.ok:
	lda #MODE_IMMEDIATE
	jmp finishKnownMode

;;; parseDirectOperand
;;;
;;; ZP_PTR0/X identify a plain operand, optionally ending in ,X or ,Y.
parseDirectOperand:
	jsr stripIndexSuffix
	jsr parseOperandCore
	bcs .coreOk
	jmp badOperand
.coreOk:
	jmp selectDirectMode

;;; parseIndirectOperand
;;;
;;; ZP_PTR0/X identify an operand beginning with '('. Recognise (value),
;;; (value,X), and (value),Y by removing punctuation from the outside inward.
parseIndirectOperand:
	jsr advanceOperandStart		; remove '('
	cpx #$02
	bcs .hasText
	jmp badOperand
.hasText:

	;; (value),Y has its index suffix outside the closing parenthesis.
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #'Y'
	bne .insideParen
	dey
	lda (ZP_PTR0),y
	cmp #','
	bne .insideParen
	dex
	dex				; remove ",Y"
	jsr stripClosingParen
	bcc badOperand
	jsr parseByteOperandCore
	bcc badOperand
	lda #MODE_INDIRECT_Y
	jmp finishKnownMode

.insideParen:
	jsr stripClosingParen
	bcc badOperand
	jsr stripIndexSuffix		; now recognises the ,X inside (value,X)
	lda operandIndex
	cmp #INDEX_Y
	beq badOperand			; (value,Y) is not a 6502 addressing form
	cmp #INDEX_X
	beq .indexedX

	jsr parseOperandCore
	bcc badOperand
	lda #MODE_INDIRECT
	jmp finishKnownMode

.indexedX:
	jsr parseByteOperandCore
	bcc badOperand
	lda #MODE_INDIRECT_X
	jmp finishKnownMode

badOperand:
	lda #INSTRUCTION_BAD_OPERAND
	rts

;;; stripClosingParen
;;;
;;; ZP_PTR0/X identify text whose final byte must be ')'. Remove it from X.
;;; Returns carry set on success. A and Y are clobbered; ZP_PTR0 is preserved.
stripClosingParen:
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #')'
	bne .bad
	dex
	beq .bad
	sec
	rts
.bad:
	clc
	rts

;;; parseByteOperandCore
;;;
;;; Parse the operand core, additionally requiring resolved numeric values to
;;; fit in one byte. Symbols are allowed because their value is not known yet.
;;; Returns carry set on success. A, X, Y and flags may be clobbered.
parseByteOperandCore:
	jsr parseOperandCore
	bcc .bad
	lda instructionOperandKind
	cmp #OPERAND_NUMBER
	bne .ok
	lda instructionOperandValue+1
	bne .bad
.ok:
	sec
	rts
.bad:
	clc
	rts

;;; finishKnownMode
;;;
;;; A = resolved MODE_*. Validate the mnemonic/mode pair against opcode_table.
;;; Returns INSTRUCTION_OK or INSTRUCTION_BAD_MODE in A.
;;; X and flags are clobbered. Y is preserved.
finishKnownMode:
	jsr tryMode
	bcc .invalid
	lda #INSTRUCTION_OK
	rts
.invalid:
	lda #INSTRUCTION_BAD_MODE
	rts

;;; tryMode
;;;
;;; A = MODE_*. Look up this mode for instructionMnemonic. If it exists, record
;;; instructionMode/instructionOpcode and return carry set. Otherwise carry is
;;; clear and the previous semantic result is left alone.
;;; A and X are clobbered. Y is preserved.
tryMode:
	pha				; keep the mode across findOpcode
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .notFound
	sta instructionOpcode
	pla
	sta instructionMode
	sec
	rts
.notFound:
	pla
	clc
	rts

;;; advanceOperandStart
;;;
;;; Advance ZP_PTR0 by one and reduce X by one. Page crossing is explicit.
;;; ZP_PTR0/X are changed; A and Y are preserved.
advanceOperandStart:
	inc ZP_PTR0
	bne .noCarry
	inc ZP_PTR0+1
.noCarry:
	dex
	rts

;;; stripIndexSuffix
;;;
;;; ZP_PTR0/X identify a direct operand. Remove a trailing ,X or ,Y from the
;;; view and record that syntax in operandIndex. A and Y are clobbered.
;;; ZP_PTR0 is preserved; X changes only when a suffix is present.
stripIndexSuffix:
	lda #INDEX_NONE
	sta operandIndex
	cpx #$03
	bcc .done

	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #'X'
	beq .x
	cmp #'Y'
	bne .done
	lda #INDEX_Y
	jmp .checkComma
.x:
	lda #INDEX_X
.checkComma:
	sta operandIndex
	dey
	lda (ZP_PTR0),y
	cmp #','
	beq .suffix
	lda #INDEX_NONE		; X or Y was part of the value, not an index suffix
	sta operandIndex
	rts
.suffix:
	dex
	dex
.done:
	rts

;;; parseOperandCore
;;;
;;; ZP_PTR0/X identify the value after addressing punctuation has been removed.
;;; '$' plus hex digits is reduced immediately to a number. Other text is kept
;;; as its source pointer/length, because a later pass may need the symbol name.
;;; Returns carry set on success. A, X, Y and flags may be clobbered.
parseOperandCore:
	cpx #$00
	beq .bad
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'$'
	beq .number

	lda #OPERAND_SYMBOL
	sta instructionOperandKind
	lda ZP_PTR0
	sta instructionSymbol
	lda ZP_PTR0+1
	sta instructionSymbol+1
	stx instructionSymbolLength
	sec
	rts
.number:
	jsr parseHex
	bcc .bad
	lda #OPERAND_NUMBER
	sta instructionOperandKind
	sec
	rts
.bad:
	clc
	rts

;;; parseHex
;;;
;;; ZP_PTR0/X = '$' followed by 1..4 uppercase hexadecimal digits.
;;; Returns the 16-bit value in instructionOperandValue and carry set.
;;; A, X, Y and flags are clobbered. ZP_PTR0 is preserved.
parseHex:
	cpx #$02
	bcc .bad
	cpx #$06
	bcs .bad

	lda #$00
	sta instructionOperandValue
	sta instructionOperandValue+1
	dex				; X is now the number of digits
	ldy #$01			; skip '$'
.next:
	lda (ZP_PTR0),y
	jsr hexNibble
	bcc .bad
	pha				; keep nibble while shifting the 16-bit value

	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	pla
	ora instructionOperandValue
	sta instructionOperandValue

	iny
	dex
	bne .next
	sec
	rts
.bad:
	clc
	rts

;;; hexNibble
;;;
;;; A = uppercase hexadecimal character. Returns its value in A and carry set,
;;; or carry clear for a non-hexadecimal character. X and Y are preserved.
hexNibble:
	cmp #'0'
	bcc .bad
	cmp #'9'+1
	bcc .decimal
	cmp #'A'
	bcc .bad
	cmp #'F'+1
	bcs .bad
	sec
	sbc #'A'-10
	sec
	rts
.decimal:
	sec
	sbc #'0'
	sec
	rts
.bad:
	clc
	rts

;;; selectDirectMode
;;;
;;; A direct operand can mean relative, zero-page, or absolute addressing.
;;; Ask opcode_table which forms exist for the mnemonic. A resolved numeric
;;; value chooses its width; a symbol is deferred only when both widths exist.
;;; Returns INSTRUCTION_OK or INSTRUCTION_BAD_MODE in A.
;;; A, X and flags are clobbered. Y is preserved.
selectDirectMode:
	;; Branch mnemonics are the only direct syntax with a relative encoding.
	lda operandIndex
	bne .notRelative
	lda #MODE_RELATIVE
	jsr tryMode
	bcs .ok

.notRelative:
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	beq .symbol

	;; A one-byte value prefers zero page, but only if that encoding exists.
	lda instructionOperandValue+1
	bne .numericLong
	ldx operandIndex
	lda directShortModes,x
	jsr tryMode
	bcs .ok
.numericLong:
	ldx operandIndex
	lda directLongModes,x
	jsr tryMode
	bcs .ok
	jmp .invalid

.symbol:
	;; Try both widths. If both exist, resolution must wait for the symbol value.
	ldx operandIndex
	lda directShortModes,x
	jsr tryMode
	bcc .longOnly
	ldx operandIndex
	lda directLongModes,x
	jsr tryMode
	bcc .ok			; short was valid and remains recorded

	lda operandIndex
	sta instructionIndex
	lda #MODE_DEFERRED
	sta instructionMode
	sta instructionOpcode
	jmp .ok

.longOnly:
	ldx operandIndex
	lda directLongModes,x
	jsr tryMode
	bcc .invalid
.ok:
	lda #INSTRUCTION_OK
	rts
.invalid:
	lda #INSTRUCTION_BAD_MODE
	rts

;;; findMnemonic
;;;
;;; ZP_PTR0 points to mnemonic text and X is its length. Returns the shared
;;; mnemonic-table index in A with carry set, or carry clear if it is unknown.
;;; ZP_PTR0 is preserved. A, X, Y and flags are clobbered.
findMnemonic:
	cpx #$03
	beq .lengthOk
	clc
	rts
.lengthOk:
	lda #$00
	sta mnemonicCandidate
.nextMnemonic:
	lda mnemonicCandidate
	asl
	clc
	adc mnemonicCandidate		; fixed-width table: offset = index * 3
	tax
	ldy #$00
.compare:
	lda (ZP_PTR0),y
	cmp mnemonic_table,x
	bne .mismatch
	iny
	inx
	cpy #$03
	bne .compare
	lda mnemonicCandidate
	sec
	rts
.mismatch:
	inc mnemonicCandidate
	lda mnemonicCandidate
	cmp #MNEMONIC_COUNT
	bne .nextMnemonic
	clc
	rts

;;; findOpcode
;;;
;;; A = shared mnemonic index, X = MODE_*. Scan the existing 256-entry
;;; opcode_table for that pair. Returns the opcode in A with carry set, or carry
;;; clear if the mnemonic has no such addressing mode.
;;; Y is preserved. A, X and flags are clobbered.
findOpcode:
	sta lookupMnemonic
	stx lookupMode
	ldx #$00
.firstPage:
	lda opcode_table,x
	cmp lookupMnemonic
	bne .nextFirst
	lda opcode_table+1,x
	cmp lookupMode
	beq .foundFirst
.nextFirst:
	inx
	inx
	bne .firstPage

	;; X wrapped to zero after 128 two-byte entries; scan the table's second page.
.secondPage:
	lda opcode_table+$100,x
	cmp lookupMnemonic
	bne .nextSecond
	lda opcode_table+$101,x
	cmp lookupMode
	beq .foundSecond
.nextSecond:
	inx
	inx
	bne .secondPage
	clc
	rts

.foundFirst:
	txa
	lsr				; table byte offset / 2 = opcode
	sec
	rts
.foundSecond:
	txa
	lsr
	ora #$80			; second half contains opcodes $80..$ff
	sec
	rts

;;; Direct addressing has the same three index choices for short and long forms.
;;; operandIndex is used only while parsing; instructionIndex is kept only if a
;;; symbolic operand leaves the short/long choice unresolved.
directShortModes:
	byte MODE_ZERO_PAGE, MODE_ZERO_PAGE_X, MODE_ZERO_PAGE_Y
directLongModes:
	byte MODE_ABSOLUTE, MODE_ABSOLUTE_X, MODE_ABSOLUTE_Y

instructionMnemonic:	byte 0
instructionMode:	byte MODE_DEFERRED
instructionOpcode:	byte MODE_DEFERRED
instructionOperandKind:	byte OPERAND_NONE
instructionOperandValue:	word 0
instructionSymbol:	word 0
instructionSymbolLength:	byte 0
instructionIndex:	byte INDEX_NONE

;; Parser scratch that does not survive as semantic instruction state.
operandIndex:	byte INDEX_NONE
mnemonicCandidate:	byte 0
lookupMnemonic:	byte 0
lookupMode:	byte 0

	include "../dis/opcode_table.asm"
	include "../dis/mnemonic_table.asm"
