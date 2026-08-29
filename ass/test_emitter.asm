	include "zp.inc"
	include "../test.inc"

FAIL_SOURCE_STATEMENT   = $01
FAIL_SOURCE_PARSE       = $02
FAIL_SOURCE_EMIT        = $03
FAIL_SOURCE_BYTES       = $04
FAIL_SOURCE_POINTER     = $05
FAIL_PAGE_BYTES         = $10
FAIL_PAGE_POINTER       = $11
FAIL_BRANCH_PLUS_127    = $20
FAIL_BRANCH_MINUS_128   = $21
FAIL_BRANCH_PLUS_128    = $22
FAIL_BRANCH_MINUS_129   = $23
FAIL_UNRESOLVED_LDA     = $30
FAIL_UNRESOLVED_JMP     = $31

PARSE_NOT_INSTRUCTION = $fe

OUTPUT                   = $2000
OUTPUT_LENGTH            = $0b
PAGE_OUTPUT              = $20ff
BRANCH_PLUS              = $2200
BRANCH_PLUS_TARGET       = $2281
BRANCH_MINUS             = $2300
BRANCH_MINUS_TARGET      = $2282
BRANCH_TOO_FAR           = $2400
BRANCH_TOO_FAR_TARGET    = $2482
BRANCH_TOO_BACK          = $2500
BRANCH_TOO_BACK_TARGET   = $2481
UNRESOLVED_OUT           = $2600

	* = TEST_ENTRY

main:
	;; Full current path: source -> statement -> instruction -> machine bytes.
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	lda #<source
	sta ZP_PTR1
	lda #>source
	sta ZP_PTR1+1
	lda #<sourceInputEnd
	sta sourceEnd
	lda #>sourceInputEnd
	sta sourceEnd+1

.sourceLoop:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .checkSourceBytes
	cmp #STATEMENT_INSTRUCTION
	beq .parseSource
	lda #FAIL_SOURCE_STATEMENT
	jmp finish
.parseSource:
	jsr parseInstruction
	cmp #INSTRUCTION_OK
	beq .emitSource
	lda #FAIL_SOURCE_PARSE
	jmp finish
.emitSource:
	jsr emitInstruction
	cmp #EMIT_OK
	beq .sourceLoop
	lda #FAIL_SOURCE_EMIT
	jmp finish

.checkSourceBytes:
	ldx #$00
.checkSourceByte:
	lda OUTPUT,x
	cmp expectedBytes,x
	beq .nextSourceByte
	lda #FAIL_SOURCE_BYTES
	jmp finish
.nextSourceByte:
	inx
	cpx #OUTPUT_LENGTH
	bne .checkSourceByte
	lda assemblyPtr
	cmp #<(OUTPUT+OUTPUT_LENGTH)
	bne .failSourcePointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+OUTPUT_LENGTH)
	beq .pageCrossing
.failSourcePointer:
	lda #FAIL_SOURCE_POINTER
	jmp finish

	;; A three-byte instruction starting at $20ff must naturally cross the page.
.pageCrossing:
	lda #<PAGE_OUTPUT
	sta assemblyPtr
	lda #>PAGE_OUTPUT
	sta assemblyPtr+1
	lda #MODE_ABSOLUTE
	sta instructionMode
	lda #$ad			; LDA absolute
	sta instructionOpcode
	lda #OPERAND_NUMBER
	sta instructionOperandKind
	lda #$34
	sta instructionOperandValue
	lda #$12
	sta instructionOperandValue+1
	jsr emitInstruction
	cmp #EMIT_OK
	beq .checkPageBytes
	lda #FAIL_PAGE_BYTES
	jmp finish
.checkPageBytes:
	lda $20ff
	cmp #$ad
	bne .failPageBytes
	lda $2100
	cmp #$34
	bne .failPageBytes
	lda $2101
	cmp #$12
	beq .checkPagePointer
.failPageBytes:
	lda #FAIL_PAGE_BYTES
	jmp finish
.checkPagePointer:
	lda assemblyPtr
	cmp #$02
	bne .failPagePointer
	lda assemblyPtr+1
	cmp #$21
	beq .branchSetup
.failPagePointer:
	lda #FAIL_PAGE_POINTER
	jmp finish

	;; Branch tests reuse one resolved BNE semantic state.
.branchSetup:
	lda #MODE_RELATIVE
	sta instructionMode
	lda #$d0
	sta instructionOpcode
	lda #OPERAND_NUMBER
	sta instructionOperandKind

	;; $2281 - ($2200 + 2) = +127.
	lda #<BRANCH_PLUS
	sta assemblyPtr
	lda #>BRANCH_PLUS
	sta assemblyPtr+1
	lda #<BRANCH_PLUS_TARGET
	sta instructionOperandValue
	lda #>BRANCH_PLUS_TARGET
	sta instructionOperandValue+1
	jsr emitInstruction
	cmp #EMIT_OK
	bne .failPlus127
	lda BRANCH_PLUS
	cmp #$d0
	bne .failPlus127
	lda BRANCH_PLUS+1
	cmp #$7f
	bne .failPlus127
	lda assemblyPtr
	cmp #$02
	bne .failPlus127
	lda assemblyPtr+1
	cmp #$22
	beq .minus128
.failPlus127:
	lda #FAIL_BRANCH_PLUS_127
	jmp finish

	;; $2282 - ($2300 + 2) = -128.
.minus128:
	lda #<BRANCH_MINUS
	sta assemblyPtr
	lda #>BRANCH_MINUS
	sta assemblyPtr+1
	lda #<BRANCH_MINUS_TARGET
	sta instructionOperandValue
	lda #>BRANCH_MINUS_TARGET
	sta instructionOperandValue+1
	jsr emitInstruction
	cmp #EMIT_OK
	bne .failMinus128
	lda BRANCH_MINUS
	cmp #$d0
	bne .failMinus128
	lda BRANCH_MINUS+1
	cmp #$80
	bne .failMinus128
	lda assemblyPtr
	cmp #$02
	bne .failMinus128
	lda assemblyPtr+1
	cmp #$23
	beq .plus128
.failMinus128:
	lda #FAIL_BRANCH_MINUS_128
	jmp finish

	;; $2482 - ($2400 + 2) = +128: fail before writing anything.
.plus128:
	lda #$5a
	sta BRANCH_TOO_FAR
	lda #$a5
	sta BRANCH_TOO_FAR+1
	lda #<BRANCH_TOO_FAR
	sta assemblyPtr
	lda #>BRANCH_TOO_FAR
	sta assemblyPtr+1
	lda #<BRANCH_TOO_FAR_TARGET
	sta instructionOperandValue
	lda #>BRANCH_TOO_FAR_TARGET
	sta instructionOperandValue+1
	jsr emitInstruction
	cmp #EMIT_BRANCH_RANGE
	bne .failPlus128
	lda assemblyPtr
	cmp #<BRANCH_TOO_FAR
	bne .failPlus128
	lda assemblyPtr+1
	cmp #>BRANCH_TOO_FAR
	bne .failPlus128
	lda BRANCH_TOO_FAR
	cmp #$5a
	bne .failPlus128
	lda BRANCH_TOO_FAR+1
	cmp #$a5
	beq .minus129
.failPlus128:
	lda #FAIL_BRANCH_PLUS_128
	jmp finish

	;; $2481 - ($2500 + 2) = -129: likewise atomic failure.
.minus129:
	lda #$3c
	sta BRANCH_TOO_BACK
	lda #$c3
	sta BRANCH_TOO_BACK+1
	lda #<BRANCH_TOO_BACK
	sta assemblyPtr
	lda #>BRANCH_TOO_BACK
	sta assemblyPtr+1
	lda #<BRANCH_TOO_BACK_TARGET
	sta instructionOperandValue
	lda #>BRANCH_TOO_BACK_TARGET
	sta instructionOperandValue+1
	jsr emitInstruction
	cmp #EMIT_BRANCH_RANGE
	bne .failMinus129
	lda assemblyPtr
	cmp #<BRANCH_TOO_BACK
	bne .failMinus129
	lda assemblyPtr+1
	cmp #>BRANCH_TOO_BACK
	bne .failMinus129
	lda BRANCH_TOO_BACK
	cmp #$3c
	bne .failMinus129
	lda BRANCH_TOO_BACK+1
	cmp #$c3
	beq .unresolvedSetup
.failMinus129:
	lda #FAIL_BRANCH_MINUS_129
	jmp finish

	;; Check both unresolved forms produced by the parser.
.unresolvedSetup:
	lda #$69
	sta UNRESOLVED_OUT
	lda #$96
	sta UNRESOLVED_OUT+1
	lda #<UNRESOLVED_OUT
	sta assemblyPtr
	lda #>UNRESOLVED_OUT
	sta assemblyPtr+1
	lda #<unresolvedSource
	sta ZP_PTR1
	lda #>unresolvedSource
	sta ZP_PTR1+1
	lda #<unresolvedSourceEnd
	sta sourceEnd
	lda #>unresolvedSourceEnd
	sta sourceEnd+1

	;; LDA target has both unresolved value and deferred zp/absolute mode.
	jsr parseNext
	cmp #INSTRUCTION_OK
	bne .failUnresolvedLda
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .failUnresolvedLda
	jsr emitInstruction
	cmp #EMIT_UNRESOLVED
	bne .failUnresolvedLda
	jsr checkUnresolvedOutput
	bcs .unresolvedJmp
.failUnresolvedLda:
	lda #FAIL_UNRESOLVED_LDA
	jmp finish

	;; JMP target has known absolute mode but its value is still unresolved.
.unresolvedJmp:
	jsr parseNext
	cmp #INSTRUCTION_OK
	bne .failUnresolvedJmp
	lda instructionMode
	cmp #MODE_ABSOLUTE
	bne .failUnresolvedJmp
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	bne .failUnresolvedJmp
	jsr emitInstruction
	cmp #EMIT_UNRESOLVED
	bne .failUnresolvedJmp
	jsr checkUnresolvedOutput
	bcs .pass
.failUnresolvedJmp:
	lda #FAIL_UNRESOLVED_JMP
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
;;; A, X, Y, ZP_PTR0 and flags are clobbered. ZP_PTR1 advances.
parseNext:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .instruction
	lda #PARSE_NOT_INSTRUCTION
	rts
.instruction:
	jmp parseInstruction

;;; checkUnresolvedOutput
;;;
;;; Verify that an unresolved emission left assemblyPtr and its two sentinel
;;; bytes unchanged. Returns carry set on success. A and flags are clobbered;
;;; X and Y are preserved.
checkUnresolvedOutput:
	lda assemblyPtr
	cmp #<UNRESOLVED_OUT
	bne .bad
	lda assemblyPtr+1
	cmp #>UNRESOLVED_OUT
	bne .bad
	lda UNRESOLVED_OUT
	cmp #$69
	bne .bad
	lda UNRESOLVED_OUT+1
	cmp #$96
	bne .bad
	sec
	rts
.bad:
	clc
	rts

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"

source:
	string "LDA #$20"
	string "STA $D020"
	string "LDX $20"
	string "JMP ($2000)"
	string "RTS"
sourceInputEnd:

expectedBytes:
	byte $a9, $20
	byte $8d, $20, $d0
	byte $a6, $20
	byte $6c, $00, $20
	byte $60

unresolvedSource:
	string "LDA target"
	string "JMP target"
unresolvedSourceEnd:
