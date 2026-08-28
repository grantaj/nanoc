	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	;; Exercise mnemonic lookup directly before parsing statements.
	lda #<mnemonicLda
	sta ZP_PTR0
	lda #>mnemonicLda
	sta ZP_PTR0+1
	ldx #$03
	jsr findMnemonic
	bcs .knownMnemonicOk
	lda #$01
	jmp finish
.knownMnemonicOk:
	sta ldaMnemonic

	lda #<mnemonicBad
	sta ZP_PTR0
	lda #>mnemonicBad
	sta ZP_PTR0+1
	ldx #$03
	jsr findMnemonic
	bcc .unknownMnemonicOk
	lda #$02
	jmp finish
.unknownMnemonicOk:

	lda #<input
	sta ZP_PTR1
	lda #>input
	sta ZP_PTR1+1
	lda #<inputEnd
	sta sourceEnd
	lda #>inputEnd
	sta sourceEnd+1

	;; RTS: implied.
	jsr parseNext
	bne .fail10
	lda instructionMode
	cmp #MODE_IMPLIED
	bne .fail10
	lda instructionOpcode
	cmp #$60
	bne .fail10
	lda instructionOperandKind
	cmp #OPERAND_NONE
	beq .case11
.fail10:
	lda #$10
	jmp finish

	;; ASL A: accumulator.
.case11:
	jsr parseNext
	bne .fail11
	lda instructionMode
	cmp #MODE_ACCUMULATOR
	bne .fail11
	lda instructionOpcode
	cmp #$0a
	beq .case12
.fail11:
	lda #$11
	jmp finish

	;; LDA #$20: immediate numeric value.
.case12:
	jsr parseNext
	bne .fail12
	lda instructionMnemonic
	cmp ldaMnemonic
	bne .fail12
	lda instructionMode
	cmp #MODE_IMMEDIATE
	bne .fail12
	lda instructionOpcode
	cmp #$a9
	bne .fail12
	lda instructionOperandKind
	cmp #OPERAND_NUMBER
	bne .fail12
	lda instructionOperandValue
	cmp #$20
	bne .fail12
	lda instructionOperandValue+1
	beq .case13
.fail12:
	lda #$12
	jmp finish

	;; LDA $20: choose zero page by parsed value and legal opcode.
.case13:
	jsr parseNext
	bne .fail13
	lda instructionMode
	cmp #MODE_ZERO_PAGE
	bne .fail13
	lda instructionOpcode
	cmp #$a5
	beq .case14
.fail13:
	lda #$13
	jmp finish

	;; LDA $2000: absolute.
.case14:
	jsr parseNext
	bne .fail14
	lda instructionMode
	cmp #MODE_ABSOLUTE
	bne .fail14
	lda instructionOpcode
	cmp #$ad
	bne .fail14
	lda instructionOperandValue
	bne .fail14
	lda instructionOperandValue+1
	cmp #$20
	beq .case15
.fail14:
	lda #$14
	jmp finish

	;; LDA $20,X: indexed zero page.
.case15:
	jsr parseNext
	bne .fail15
	lda instructionMode
	cmp #MODE_ZERO_PAGE_X
	bne .fail15
	lda instructionOpcode
	cmp #$b5
	beq .case16
.fail15:
	lda #$15
	jmp finish

	;; LDA $2000,X: indexed absolute.
.case16:
	jsr parseNext
	bne .fail16
	lda instructionMode
	cmp #MODE_ABSOLUTE_X
	bne .fail16
	lda instructionOpcode
	cmp #$bd
	beq .case17
.fail16:
	lda #$16
	jmp finish

	;; LDX $20,Y: indexed zero page Y.
.case17:
	jsr parseNext
	bne .fail17
	lda instructionMode
	cmp #MODE_ZERO_PAGE_Y
	bne .fail17
	lda instructionOpcode
	cmp #$b6
	beq .case18
.fail17:
	lda #$17
	jmp finish

	;; LDX $2000,Y: indexed absolute Y.
.case18:
	jsr parseNext
	bne .fail18
	lda instructionMode
	cmp #MODE_ABSOLUTE_Y
	bne .fail18
	lda instructionOpcode
	cmp #$be
	beq .case19
.fail18:
	lda #$18
	jmp finish

	;; JMP ($2000): absolute indirect.
.case19:
	jsr parseNext
	bne .fail19
	lda instructionMode
	cmp #MODE_INDIRECT
	bne .fail19
	lda instructionOpcode
	cmp #$6c
	beq .case1a
.fail19:
	lda #$19
	jmp finish

	;; LDA ($20,X): indexed indirect X.
.case1a:
	jsr parseNext
	bne .fail1a
	lda instructionMode
	cmp #MODE_INDIRECT_X
	bne .fail1a
	lda instructionOpcode
	cmp #$a1
	beq .case1b
.fail1a:
	lda #$1a
	jmp finish

	;; LDA ($20),Y: indirect indexed Y.
.case1b:
	jsr parseNext
	bne .fail1b
	lda instructionMode
	cmp #MODE_INDIRECT_Y
	bne .fail1b
	lda instructionOpcode
	cmp #$b1
	beq .case1c
.fail1b:
	lda #$1b
	jmp finish

	;; BNE target address: the opcode table tells us this mnemonic is relative.
.case1c:
	jsr parseNext
	bne .fail1c
	lda instructionMode
	cmp #MODE_RELATIVE
	bne .fail1c
	lda instructionOpcode
	cmp #$d0
	bne .fail1c
	lda instructionOperandValue+1
	cmp #$c0
	beq .case1d
.fail1c:
	lda #$1c
	jmp finish

	;; JMP target: symbol is retained in place; JMP has only the absolute form.
.case1d:
	jsr parseNext
	bne .fail1d
	lda instructionMode
	cmp #MODE_ABSOLUTE
	bne .fail1d
	lda instructionOpcode
	cmp #$4c
	bne .fail1d
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	bne .fail1d
	lda instructionSymbol
	cmp #<jmpSymbol
	bne .fail1d
	lda instructionSymbol+1
	cmp #>jmpSymbol
	bne .fail1d
	lda instructionSymbolLength
	cmp #$06
	beq .case1e
.fail1d:
	lda #$1d
	jmp finish

	;; LDA target: both zp and absolute exist, so mode resolution is deferred.
.case1e:
	jsr parseNext
	bne .fail1e
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .fail1e
	lda instructionOpcode
	cmp #$ff
	bne .fail1e
	lda instructionIndex
	cmp #INDEX_NONE
	bne .fail1e
	lda instructionSymbol
	cmp #<ldaSymbol
	bne .fail1e
	lda instructionSymbol+1
	cmp #>ldaSymbol
	beq .case1f
.fail1e:
	lda #$1e
	jmp finish

	;; Unknown mnemonic is distinct from a bad mnemonic/mode pair.
.case1f:
	jsr parseNext
	cmp #INSTRUCTION_BAD_MNEMONIC
	beq .case20
	lda #$1f
	jmp finish

	;; STA immediate has a known mnemonic but no such opcode.
.case20:
	jsr parseNext
	cmp #INSTRUCTION_BAD_MODE
	beq .reverseLookup
	lda #$20
	jmp finish

	;; Reverse lookup reuses opcode_table: LDA/immediate -> $A9.
.reverseLookup:
	lda ldaMnemonic
	ldx #MODE_IMMEDIATE
	jsr findOpcode
	bcc .fail21
	cmp #$a9
	beq .invalidPair
.fail21:
	lda #$21
	jmp finish

	;; The STA mnemonic from the failed parse remains available; STA/immediate
	;; must not be found in the opcode table.
.invalidPair:
	lda instructionMnemonic
	ldx #MODE_IMMEDIATE
	jsr findOpcode
	bcc .eof
	lda #$22
	jmp finish

.eof:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .pass
	lda #$23
	jmp finish

.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; parseNext
;;; Parse the next statement and require it to be an instruction.
;;; Returns parseInstruction status in A, or $fe if statement recognition fails.
parseNext:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .instruction
	lda #$fe
	rts
.instruction:
	jsr parseInstruction
	rts

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
