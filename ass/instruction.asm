;;; instruction.asm
;;;
;;; Parse a STATEMENT_INSTRUCTION directly from the zero-copy views produced by
;;; nextStatement. The existing disassembler tables remain the authoritative
;;; description of mnemonics, addressing modes, and opcodes.
;;;
;;; parseInstruction output:
;;;   A                       status (INSTRUCTION_*)
;;;   instructionMnemonic     mnemonic-table index
;;;   instructionMode         MODE_* or MODE_DEFERRED for unresolved zp/abs
;;;   instructionOpcode       opcode, or $ff while mode is deferred
;;;   instructionOperandKind  OPERAND_NONE / NUMBER / SYMBOL
;;;   instructionOperandValue 16-bit numeric value
;;;   instructionSymbol       zero-copy pointer/length for symbolic operands
;;;   instructionIndex        INDEX_* only needed while mode is deferred
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
MNEMONIC_COUNT = $38		; index $38 in the table is the ??? sentinel

parseInstruction:
	lda #MODE_DEFERRED
	sta instructionMode
	sta instructionOpcode
	lda #OPERAND_NONE
	sta instructionOperandKind
	lda #INDEX_NONE
	sta instructionIndex
	lda #$00
	sta instructionOperandValue
	sta instructionOperandValue+1
	sta instructionSymbolLength

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
	bne .operand
	lda #MODE_IMPLIED
	jmp finishKnownMode

.operand:
	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldx statementArgumentLength

	;; A by itself is the accumulator form.
	cpx #$01
	bne .notAccumulator
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'A'
	bne .direct
	lda #MODE_ACCUMULATOR
	jmp finishKnownMode

.notAccumulator:
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'#'
	beq .immediate
	cmp #'('
	beq .indirect

.direct:
	jsr stripIndexSuffix		; Y = INDEX_*, X/core adjusted
	sty instructionIndex
	jsr parseOperandCore
	bcs .directCoreOk
	jmp .badOperand
.directCoreOk:
	jsr selectDirectMode
	bcs .directModeOk
	jmp .badMode
.directModeOk:
	lda #INSTRUCTION_OK
	rts

.immediate:
	jsr advanceOperandStart
	jsr parseOperandCore
	bcc .badOperand
	jsr requireByteIfNumeric
	bcc .badOperand
	lda #MODE_IMMEDIATE
	jmp finishKnownMode

.indirect:
	jsr advanceOperandStart		; remove '('
	cpx #$02
	bcc .badOperand

	;; (...),Y
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #'Y'
	bne .endsParen
	dey
	lda (ZP_PTR0),y
	cmp #','
	bne .badOperand
	dey
	lda (ZP_PTR0),y
	cmp #')'
	bne .badOperand
	txa
	sec
	sbc #$03
	tax
	beq .badOperand
	jsr parseOperandCore
	bcc .badOperand
	jsr requireByteIfNumeric
	bcc .badOperand
	lda #MODE_INDIRECT_Y
	jmp finishKnownMode

.endsParen:
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #')'
	bne .badOperand
	dex				; remove trailing ')'
	beq .badOperand

	;; (...,X)
	cpx #$03
	bcc .plainIndirect
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #'X'
	bne .plainIndirect
	dey
	lda (ZP_PTR0),y
	cmp #','
	bne .plainIndirect
	dex
	dex				; remove ",X"
	beq .badOperand
	jsr parseOperandCore
	bcc .badOperand
	jsr requireByteIfNumeric
	bcc .badOperand
	lda #MODE_INDIRECT_X
	jmp finishKnownMode

.plainIndirect:
	jsr parseOperandCore
	bcc .badOperand
	lda #MODE_INDIRECT
	jmp finishKnownMode

.badOperand:
	lda #INSTRUCTION_BAD_OPERAND
	rts
.badMode:
	lda #INSTRUCTION_BAD_MODE
	rts

;;; finishKnownMode
;;;
;;; A = resolved MODE_*. Validate against the opcode table and record opcode.
finishKnownMode:
	sta instructionMode
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .invalid
	sta instructionOpcode
	lda #INSTRUCTION_OK
	rts
.invalid:
	lda #INSTRUCTION_BAD_MODE
	rts

;;; advanceOperandStart
;;;
;;; Advance ZP_PTR0 and reduce X by one. Carry across a source page explicitly.
advanceOperandStart:
	inc ZP_PTR0
	bne .noCarry
	inc ZP_PTR0+1
.noCarry:
	dex
	rts

;;; stripIndexSuffix
;;;
;;; Input ZP_PTR0/X = direct operand view. If it ends in ,X or ,Y, remove the
;;; suffix from X. Return Y = INDEX_NONE/X/Y.
stripIndexSuffix:
	ldy #INDEX_NONE
	cpx #$03
	bcc .done
	txa
	pha
	tay
	dey
	lda (ZP_PTR0),y
	cmp #'X'
	beq .x
	cmp #'Y'
	beq .y
	pla
	tax
	ldy #INDEX_NONE
	rts
.x:
	lda #INDEX_X
	jmp .checkComma
.y:
	lda #INDEX_Y
.checkComma:
	pha
	dey
	lda (ZP_PTR0),y
	cmp #','
	bne .notSuffix
	pla
	tay
	pla
	tax
	dex
	dex
	rts
.notSuffix:
	pla
	pla
	tax
	ldy #INDEX_NONE
.done:
	rts

;;; parseOperandCore
;;;
;;; ZP_PTR0/X identify the value inside any operand punctuation. $hhhh is
;;; parsed immediately; other text is retained as a zero-copy symbol view.
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
;;; ZP_PTR0/X = '$' plus 1..4 uppercase hexadecimal digits.
;;; Returns instructionOperandValue and carry set on success.
parseHex:
	cpx #$02
	bcc .bad
	cpx #$06
	bcs .bad
	stx operandLength
	lda #$00
	sta instructionOperandValue
	sta instructionOperandValue+1
	ldy #$01
.next:
	lda (ZP_PTR0),y
	jsr hexNibble
	bcc .bad
	sta operandNibble

	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	asl instructionOperandValue
	rol instructionOperandValue+1
	lda instructionOperandValue
	ora operandNibble
	sta instructionOperandValue

	iny
	cpy operandLength
	bne .next
	sec
	rts
.bad:
	clc
	rts

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

requireByteIfNumeric:
	lda instructionOperandKind
	cmp #OPERAND_NUMBER
	bne .ok
	lda instructionOperandValue+1
	beq .ok
	clc
	rts
.ok:
	sec
	rts

;;; selectDirectMode
;;;
;;; Select relative, zero-page, or absolute forms by asking the opcode table
;;; which encodings exist for this mnemonic. Symbolic operands with both short
;;; and long encodings remain MODE_DEFERRED until symbol resolution.
selectDirectMode:
	lda instructionIndex
	bne .choosePair
	lda instructionMnemonic
	ldx #MODE_RELATIVE
	jsr findOpcode
	bcc .choosePair
	sta instructionOpcode
	lda #MODE_RELATIVE
	sta instructionMode
	sec
	rts

.choosePair:
	lda instructionIndex
	cmp #INDEX_X
	beq .x
	cmp #INDEX_Y
	beq .y
	lda #MODE_ZERO_PAGE
	sta shortMode
	lda #MODE_ABSOLUTE
	sta longMode
	jmp .ready
.x:
	lda #MODE_ZERO_PAGE_X
	sta shortMode
	lda #MODE_ABSOLUTE_X
	sta longMode
	jmp .ready
.y:
	lda #MODE_ZERO_PAGE_Y
	sta shortMode
	lda #MODE_ABSOLUTE_Y
	sta longMode

.ready:
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	beq .symbol

	lda instructionOperandValue+1
	bne .long
	lda instructionMnemonic
	ldx shortMode
	jsr findOpcode
	bcc .long
	sta instructionOpcode
	lda shortMode
	sta instructionMode
	sec
	rts
.long:
	lda instructionMnemonic
	ldx longMode
	jsr findOpcode
	bcc .invalid
	sta instructionOpcode
	lda longMode
	sta instructionMode
	sec
	rts

.symbol:
	lda #$00
	sta shortAvailable
	lda instructionMnemonic
	ldx shortMode
	jsr findOpcode
	bcc .symbolLong
	sta shortOpcode
	inc shortAvailable
.symbolLong:
	lda instructionMnemonic
	ldx longMode
	jsr findOpcode
	bcc .onlyShort
	sta longOpcode
	lda shortAvailable
	beq .onlyLong
	lda #MODE_DEFERRED
	sta instructionMode
	sta instructionOpcode
	sec
	rts
.onlyLong:
	lda longOpcode
	sta instructionOpcode
	lda longMode
	sta instructionMode
	sec
	rts
.onlyShort:
	lda shortAvailable
	beq .invalid
	lda shortOpcode
	sta instructionOpcode
	lda shortMode
	sta instructionMode
	sec
	rts
.invalid:
	clc
	rts

;;; findMnemonic
;;;
;;; ZP_PTR0 points to text and X is its length. Returns mnemonic index in A and
;;; carry set, or carry clear when the three-byte mnemonic is unknown.
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
	adc mnemonicCandidate
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
;;; A = mnemonic index, X = MODE_*. Linear scan of the existing 512-byte table.
;;; Returns opcode in A and carry set, or carry clear if the pair is invalid.
findOpcode:
	sta lookupMnemonic
	stx lookupMode
	lda #$00
	sta opcodeCandidate
	ldx #$00
.firstPage:
	lda opcode_table,x
	cmp lookupMnemonic
	bne .nextFirst
	lda opcode_table+1,x
	cmp lookupMode
	beq .found
.nextFirst:
	inc opcodeCandidate
	inx
	inx
	bne .firstPage
.secondPage:
	lda opcode_table+$100,x
	cmp lookupMnemonic
	bne .nextSecond
	lda opcode_table+$101,x
	cmp lookupMode
	beq .found
.nextSecond:
	inc opcodeCandidate
	inx
	inx
	bne .secondPage
	clc
	rts
.found:
	lda opcodeCandidate
	sec
	rts

instructionMnemonic:	byte 0
instructionMode:	byte MODE_DEFERRED
instructionOpcode:	byte MODE_DEFERRED
instructionOperandKind:	byte OPERAND_NONE
instructionOperandValue:	word 0
instructionSymbol:	word 0
instructionSymbolLength:	byte 0
instructionIndex:	byte INDEX_NONE

operandLength:	byte 0
operandNibble:	byte 0
shortMode:	byte 0
longMode:	byte 0
shortAvailable:	byte 0
shortOpcode:	byte 0
longOpcode:	byte 0
mnemonicCandidate:	byte 0
lookupMnemonic:	byte 0
lookupMode:	byte 0
opcodeCandidate:	byte 0

	include "../dis/opcode_table.asm"
	include "../dis/mnemonic_table.asm"
