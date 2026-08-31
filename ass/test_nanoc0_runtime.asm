	include "../test.inc"

RT_GENERATED_ENTRY = $0800
RT_SMOKE_TARGET    = $2000

RT_FAIL_GENERATED_ASSEMBLE = $20
RT_FAIL_GENERATED_VALUE    = $40
RT_FAIL_SMOKE_ASSEMBLE     = $60
RT_FAIL_SMOKE_BYTE         = $70

	* = ASSEMBLER_TEST_ENTRY

main:
	lda #<runtimeGeneratedName
	sta ASSEMBLER_COMMAND_NAME
	lda #>runtimeGeneratedName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #runtimeGeneratedNameEnd-runtimeGeneratedName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<RT_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET
	lda #>RT_GENERATED_ENTRY
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .run
	ora #RT_FAIL_GENERATED_ASSEMBLE
	jmp .finish

.run:
	jsr RT_GENERATED_ENTRY
	sta rtReturnedLow
	stx rtReturnedHigh
	ora rtReturnedHigh
	beq .smoke
	lda rtReturnedLow
	bne .finish
	lda #RT_FAIL_GENERATED_VALUE
	jmp .finish

.smoke:
	lda #<smokeName
	sta ASSEMBLER_COMMAND_NAME
	lda #>smokeName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #smokeNameEnd-smokeName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<RT_SMOKE_TARGET
	sta ASSEMBLER_COMMAND_TARGET
	lda #>RT_SMOKE_TARGET
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .checkByte
	ora #RT_FAIL_SMOKE_ASSEMBLE
	jmp .finish

.checkByte:
	lda RT_SMOKE_TARGET
	cmp #$2a
	beq .pass
	lda #RT_FAIL_SMOKE_BYTE
	jmp .finish
.pass:
	lda #TEST_PASS
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

runtimeGeneratedName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','R','U','N','T','I','M','E','/','R','T','O','U','T','.','A','S','M'
runtimeGeneratedNameEnd:
smokeName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','R','U','N','T','I','M','E','/','S','M','O','K','E','.','A','S','M'
smokeNameEnd:

rtReturnedLow:	byte 0
rtReturnedHigh:	byte 0

	include "ass.asm"
