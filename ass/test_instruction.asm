	include "zp.inc"
	include "../test.inc"

FAIL_KNOWN_MNEMONIC   = $01
FAIL_UNKNOWN_MNEMONIC = $02
FAIL_PAGE_ADVANCE     = $03
FAIL_RTS              = $10
FAIL_ACCUMULATOR      = $11
FAIL_IMMEDIATE        = $12
FAIL_ZERO_PAGE        = $13
FAIL_ABSOLUTE         = $14
FAIL_ZERO_PAGE_X      = $15
FAIL_ABSOLUTE_X       = $16
FAIL_ZERO_PAGE_Y      = $17
FAIL_ABSOLUTE_Y       = $18
FAIL_INDIRECT         = $19
FAIL_INDIRECT_X       = $1a
FAIL_INDIRECT_Y       = $1b
FAIL_RELATIVE         = $1c
FAIL_SYMBOL_ABSOLUTE  = $1d
FAIL_SYMBOL_DEFERRED  = $1e
FAIL_BAD_MNEMONIC     = $1f
FAIL_BAD_MODE         = $20
FAIL_OPCODE_LOOKUP    = $21
FAIL_INVALID_PAIR     = $22
FAIL_EOF              = $23

PARSE_NOT_INSTRUCTION = $fe

	* = TEST_ENTRY

main:
	;; The shared mnemonic table supplies the assembler's mnemonic IDs.
	lda #<mnemonicLda
	sta ZP_PTR0
	lda #>mnemonicLda
	sta ZP_PTR0+1
	ldx #$03
	jsr findMnemonic
	bcs .knownMnemonic
	lda #FAIL_KNOWN_MNEMONIC
	jmp finish
.knownMnemonic:
	sta ldaMnemonic

	lda #<mnemonicBad
	sta ZP_PTR0
	lda #>mnemonicBad
	sta ZP_PTR0+1
	ldx #$03
	jsr findMnemonic
	bcc .pageAdvance
	lda #FAIL_UNKNOWN_MNEMONIC
	jmp finish

	;; advanceOperandStart is the one new parser helper that changes a pointer.
	;; Check its 16-bit page crossing directly.
.pageAdvance:
	lda #$ff
	sta ZP_PTR0
	lda #$12
	sta ZP_PTR0+1
	ldx #$02
	jsr advanceOperandStart
	lda ZP_PTR0
	bne .failPageAdvance
	lda ZP_PTR0+1
	cmp #$13
	bne .failPageAdvance
	cpx #$01
	beq .startSource
.failPageAdvance:
	lda #FAIL_PAGE_ADVANCE
	jmp finish

.startSource:
	lda #<input
	sta ZP_PTR1
	lda #>input
	sta ZP_PTR1+1
	lda #<inputEnd
	sta sourceEnd
	lda #>inputEnd
	sta sourceEnd+1

	;; RTS: implied.
.rts:
	jsr parseNext
	bne .failRts
	lda instructionMode
	cmp #MODE_IMPLIED
	bne .failRts
	lda instructionOpcode
	cmp #$60
	bne .failRts
	lda instructionOperandKind
	cmp #OPERAND_NONE
	beq .accumulator
.failRts:
	lda #FAIL_RTS
	jmp finish

	;; ASL A: accumulator.
.accumulator:
	jsr parseNext
	bne .failAccumulator
	lda instructionMode
	cmp #MODE_ACCUMULATOR
	bne .failAccumulator
	lda instructionOpcode
	cmp #$0a
	beq .immediate
.failAccumulator:
	lda #FAIL_ACCUMULATOR
	jmp finish

	;; LDA #$20: immediate numeric value.
.immediate:
	jsr parseNext
	bne .failImmediate
	lda instructionMnemonic
	cmp ldaMnemonic
	bne .failImmediate
	lda instructionMode
	cmp #MODE_IMMEDIATE
	bne .failImmediate
	lda instructionOpcode
	cmp #$a9
	bne .failImmediate
	lda instructionOperandKind
	cmp #OPERAND_NUMBER
	bne .failImmediate
	lda instructionOperandValue
	cmp #$20
	bne .failImmediate
	lda instructionOperandValue+1
	beq .zeroPage
.failImmediate:
	lda #FAIL_IMMEDIATE
	jmp finish

	;; LDA $20: the parsed value permits zero-page encoding.
.zeroPage:
	jsr parseNext
	bne .failZeroPage
	lda instructionMode
	cmp #MODE_ZERO_PAGE
	bne .failZeroPage
	lda instructionOpcode
	cmp #$a5
	beq .absolute
.failZeroPage:
	lda #FAIL_ZERO_PAGE
	jmp finish

	;; LDA $2000: the value requires absolute encoding.
.absolute:
	jsr parseNext
	bne .failAbsolute
	lda instructionMode
	cmp #MODE_ABSOLUTE
	bne .failAbsolute
	lda instructionOpcode
	cmp #$ad
	bne .failAbsolute
	lda instructionOperandValue
	bne .failAbsolute
	lda instructionOperandValue+1
	cmp #$20
	beq .zeroPageX
.failAbsolute:
	lda #FAIL_ABSOLUTE
	jmp finish

	;; LDA $20,X: resolved mode carries the X indexing fact by itself.
.zeroPageX:
	jsr parseNext
	bne .failZeroPageX
	lda instructionMode
	cmp #MODE_ZERO_PAGE_X
	bne .failZeroPageX
	lda instructionOpcode
	cmp #$b5
	bne .failZeroPageX
	lda instructionIndex
	cmp #INDEX_NONE
	beq .absoluteX
.failZeroPageX:
	lda #FAIL_ZERO_PAGE_X
	jmp finish

	;; LDA $2000,X: indexed absolute.
.absoluteX:
	jsr parseNext
	bne .failAbsoluteX
	lda instructionMode
	cmp #MODE_ABSOLUTE_X
	bne .failAbsoluteX
	lda instructionOpcode
	cmp #$bd
	beq .zeroPageY
.failAbsoluteX:
	lda #FAIL_ABSOLUTE_X
	jmp finish

	;; LDX $20,Y: indexed zero page Y.
.zeroPageY:
	jsr parseNext
	bne .failZeroPageY
	lda instructionMode
	cmp #MODE_ZERO_PAGE_Y
	bne .failZeroPageY
	lda instructionOpcode
	cmp #$b6
	beq .absoluteY
.failZeroPageY:
	lda #FAIL_ZERO_PAGE_Y
	jmp finish

	;; LDX $2000,Y: indexed absolute Y.
.absoluteY:
	jsr parseNext
	bne .failAbsoluteY
	lda instructionMode
	cmp #MODE_ABSOLUTE_Y
	bne .failAbsoluteY
	lda instructionOpcode
	cmp #$be
	beq .indirect
.failAbsoluteY:
	lda #FAIL_ABSOLUTE_Y
	jmp finish

	;; JMP ($2000): absolute indirect.
.indirect:
	jsr parseNext
	bne .failIndirect
	lda instructionMode
	cmp #MODE_INDIRECT
	bne .failIndirect
	lda instructionOpcode
	cmp #$6c
	beq .indirectX
.failIndirect:
	lda #FAIL_INDIRECT
	jmp finish

	;; LDA ($20,X): indexed indirect X.
.indirectX:
	jsr parseNext
	bne .failIndirectX
	lda instructionMode
	cmp #MODE_INDIRECT_X
	bne .failIndirectX
	lda instructionOpcode
	cmp #$a1
	beq .indirectY
.failIndirectX:
	lda #FAIL_INDIRECT_X
	jmp finish

	;; LDA ($20),Y: indirect indexed Y.
.indirectY:
	jsr parseNext
	bne .failIndirectY
	lda instructionMode
	cmp #MODE_INDIRECT_Y
	bne .failIndirectY
	lda instructionOpcode
	cmp #$b1
	beq .relative
.failIndirectY:
	lda #FAIL_INDIRECT_Y
	jmp finish

	;; BNE $C000: opcode metadata identifies branch mnemonics as relative.
.relative:
	jsr parseNext
	bne .failRelative
	lda instructionMode
	cmp #MODE_RELATIVE
	bne .failRelative
	lda instructionOpcode
	cmp #$d0
	bne .failRelative
	lda instructionOperandValue+1
	cmp #$c0
	beq .symbolAbsolute
.failRelative:
	lda #FAIL_RELATIVE
	jmp finish

	;; JMP target: only absolute exists, so the symbol does not make mode unclear.
.symbolAbsolute:
	jsr parseNext
	bne .failSymbolAbsolute
	lda instructionMode
	cmp #MODE_ABSOLUTE
	bne .failSymbolAbsolute
	lda instructionOpcode
	cmp #$4c
	bne .failSymbolAbsolute
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	bne .failSymbolAbsolute
	lda instructionSymbol
	cmp #<jmpSymbol
	bne .failSymbolAbsolute
	lda instructionSymbol+1
	cmp #>jmpSymbol
	bne .failSymbolAbsolute
	lda instructionSymbolLength
	cmp #$06
	beq .symbolDeferred
.failSymbolAbsolute:
	lda #FAIL_SYMBOL_ABSOLUTE
	jmp finish

	;; LDA target: both zero-page and absolute exist, so width is deferred.
.symbolDeferred:
	jsr parseNext
	bne .failSymbolDeferred
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .failSymbolDeferred
	lda instructionOpcode
	cmp #$ff
	bne .failSymbolDeferred
	lda instructionIndex
	cmp #INDEX_NONE
	bne .failSymbolDeferred
	lda instructionSymbol
	cmp #<ldaSymbol
	bne .failSymbolDeferred
	lda instructionSymbol+1
	cmp #>ldaSymbol
	beq .badMnemonic
.failSymbolDeferred:
	lda #FAIL_SYMBOL_DEFERRED
	jmp finish

	;; Unknown mnemonic is distinct from a known mnemonic with an illegal mode.
.badMnemonic:
	jsr parseNext
	cmp #INSTRUCTION_BAD_MNEMONIC
	beq .badMode
	lda #FAIL_BAD_MNEMONIC
	jmp finish

	;; STA immediate has a known mnemonic but no such opcode.
.badMode:
	jsr parseNext
	cmp #INSTRUCTION_BAD_MODE
	beq .opcodeLookup
	lda #FAIL_BAD_MODE
	jmp finish

	;; Reverse lookup reuses opcode_table: LDA/immediate -> $A9.
.opcodeLookup:
	lda ldaMnemonic
	ldx #MODE_IMMEDIATE
	jsr findOpcode
	bcc .failOpcodeLookup
	cmp #$a9
	beq .invalidPair
.failOpcodeLookup:
	lda #FAIL_OPCODE_LOOKUP
	jmp finish

	;; The failed STA parse left its known mnemonic ID in instructionMnemonic.
.invalidPair:
	lda instructionMnemonic
	ldx #MODE_IMMEDIATE
	jsr findOpcode
	bcc .eof
	lda #FAIL_INVALID_PAIR
	jmp finish

.eof:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .pass
	lda #FAIL_EOF
	jmp finish

.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; parseNext
;;;
;;; Parse the next statement and require an instruction.
;;; Returns parseInstruction status in A, or PARSE_NOT_INSTRUCTION.
;;; A, X, Y, ZP_PTR0 and flags are clobbered. ZP_PTR1 advances to the next line.
parseNext:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .instruction
	lda #PARSE_NOT_INSTRUCTION
	rts
.instruction:
	jmp parseInstruction

ldaMnemonic:
	byte 0

mnemonicLda:
	byte 'L','D','A'
mnemonicBad:
	byte 'X','Y','Z'

	include "parser.asm"
	include "instruction.asm"

input:
	string "RTS"
	string "ASL A"
	string "LDA #$20"
	string "LDA $20"
	string "LDA $2000"
	string "LDA $20,X"
	string "LDA $2000,X"
	string "LDX $20,Y"
	string "LDX $2000,Y"
	string "JMP ($2000)"
	string "LDA ($20,X)"
	string "LDA ($20),Y"
	string "BNE $C000"
	byte 'J','M','P',' '
jmpSymbol:
	string "target"
	byte 'L','D','A',' '
ldaSymbol:
	string "target"
	string "XYZ $20"
	string "STA #$20"
inputEnd:
