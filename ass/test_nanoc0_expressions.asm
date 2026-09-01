	include "../test.inc"

XT_GENERATED_ENTRY = $0800

;;; Arena cursors saved with TEST_RESULT. They are diagnostics only: the result
;;; byte remains the authority, while a SYMBOL_FULL failure says which fixed
;;; production arena actually reached its boundary.
XT_PERSIST_END = $03
XT_OVERFLOW_END = $05
XT_LOCAL_END = $07

;;; The production assembler occupies $4000 upward. It assembles the source
;;; emitted by nanoc0/test_expression_compile.asm into $0800, then this test
;;; executes those generated instructions and publishes their native result.
;;;
;;; If assembly itself fails, return the assembler status directly. The status
;;; constants are already meaningful diagnostics, so wrapping them in a test-only
;;; error code would only hide useful information.
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
	pha
	jsr captureArenas
	pla
	cmp #ASSEMBLE_OK
	beq .run
	jmp .finish
.run:
	jsr XT_GENERATED_ENTRY
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

captureArenas:
	lda symbolTableEnd
	sta XT_PERSIST_END
	lda symbolTableEnd+1
	sta XT_PERSIST_END+1
	lda symbolOverflowEnd
	sta XT_OVERFLOW_END
	lda symbolOverflowEnd+1
	sta XT_OVERFLOW_END+1
	lda localSymbolTableEnd
	sta XT_LOCAL_END
	lda localSymbolTableEnd+1
	sta XT_LOCAL_END+1
	rts

generatedName:	byte 'E','X','P','R','O','U','T','.','A','S','M'
generatedNameEnd:

	include "ass.asm"
