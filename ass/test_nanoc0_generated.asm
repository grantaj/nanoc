	include "../test.inc"

GENERATED_ENTRY = $0800

FAIL_ASSEMBLE_GENERATED = $30
FAIL_GENERATED_RESULT   = $40

	* = ASSEMBLER_TEST_ENTRY

main:
	lda #<generatedName
	sta ASSEMBLER_COMMAND_NAME
	lda #>generatedName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #generatedNameEnd-generatedName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET
	lda #>GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .run
	ora #FAIL_ASSEMBLE_GENERATED
	jmp finish

.run:
	jsr GENERATED_ENTRY
	cmp #'Z'
	bne .badResult
	cpx #$00
	bne .badResult
	lda #TEST_PASS
	jmp finish
.badResult:
	lda #FAIL_GENERATED_RESULT
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

generatedName:
	byte 'N','C','O','U','T','.','A','S','M'
generatedNameEnd:

	include "ass.asm"
