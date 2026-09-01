	include "../test.inc"

XT_GENERATED_ENTRY = $0800
XT_TEST_ENTRY      = $2c00

;;; Arena cursors saved with TEST_RESULT. They are diagnostics only: the result
;;; byte remains the authority, while a SYMBOL_FULL failure says which fixed
;;; production arena actually reached its boundary.
XT_PERSIST_END = $03
XT_OVERFLOW_END = $05
XT_LOCAL_END = $07

;;; Keep the small test harness below ass's command block. The production
;;; assembler itself begins at exactly $4000 and therefore ends below its fixed
;;; $6000 staging buffer. Generated expression code starts at $0800.
	* = XT_TEST_ENTRY

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

;;; The execution pass mounts the repository root so generated source can include
;;; the same target helpers production nanoc0 emits.
generatedName:	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','E','X','P','R','/','E','X','P','R','O','U','T','.','A','S','M'
generatedNameEnd:

	* = ASSEMBLER_TEST_ENTRY
	include "ass.asm"
