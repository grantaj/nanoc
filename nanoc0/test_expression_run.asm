	include "../test.inc"

XT_GENERATED_ENTRY = $0800
XT_FAIL_ASSEMBLE   = $40

;;; The production assembler occupies $4000 upward. It assembles the source
;;; emitted by test_expression_compile.asm into $0800, then this test executes
;;; those generated instructions and publishes their native result unchanged.
	* = ASSEMBLER_TEST_ENTRY

main:
	lda #<generatedName
	sta ASSEMBLER_COMMAND_NAME
	lda #>generatedName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #generatedNameEnd-generatedName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<XT_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET
	lda #>XT_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET+1

	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .run
	lda #XT_FAIL_ASSEMBLE
	jmp .finish
.run:
	jsr XT_GENERATED_ENTRY
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

generatedName:	byte 'E','X','P','R','O','U','T','.','A','S','M'
generatedNameEnd:

	include "../ass/ass.asm"
