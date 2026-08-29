	include "../test.inc"

SELF_HOSTED  = $0800
SMOKE_OUTPUT = $3400

FAIL_BUILD_B     = $10
FAIL_RUN_B       = $20
FAIL_SMOKE_BYTES = $30

	* = ASSEMBLER_TEST_ENTRY

main:
	;; A is the vasm-built copy in this test image. Use it to assemble the real
	;; production ass source tree into B at $0800.
	lda #<selfName
	sta ASSEMBLER_COMMAND_NAME
	lda #>selfName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #selfNameEnd-selfName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<SELF_HOSTED
	sta ASSEMBLER_COMMAND_TARGET
	lda #>SELF_HOSTED
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr assemblerEntry
	cmp #ASSEMBLE_OK
	beq .builtB
	ora #FAIL_BUILD_B
	jmp finish

.builtB:
	;; Execute B itself and use it to assemble a tiny known program. Successful
	;; output proves the generated image is not merely plausible bytes in memory.
	lda #<smokeName
	sta ASSEMBLER_COMMAND_NAME
	lda #>smokeName
	sta ASSEMBLER_COMMAND_NAME+1
	lda #smokeNameEnd-smokeName
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<SMOKE_OUTPUT
	sta ASSEMBLER_COMMAND_TARGET
	lda #>SMOKE_OUTPUT
	sta ASSEMBLER_COMMAND_TARGET+1
	jsr SELF_HOSTED
	lda ASSEMBLER_COMMAND_STATUS
	beq .checkSmoke
	ora #FAIL_RUN_B
	jmp finish

.checkSmoke:
	ldx #$00
.loop:
	lda SMOKE_OUTPUT,x
	cmp expectedSmoke,x
	bne .badSmoke
	inx
	cpx #expectedSmokeEnd-expectedSmoke
	bne .loop
	lda #TEST_PASS
	jmp finish

.badSmoke:
	lda #FAIL_SMOKE_BYTES
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; The self-host test mounts the repository root. These are already in the C64
;;; upper-case filename form expected by VICE's host filesystem device.
selfName:
	byte 'A','S','S','/','A','S','S','_','0','8','0','0','.','A','S','M'
selfNameEnd:
smokeName:
	byte 'A','S','S','/','S','E','L','F','H','O','S','T','_','S','M','O','K','E','.','A','S','M'
smokeNameEnd:

expectedSmoke:
	byte $a9,$2a,$8d,$20,$d0,$60
expectedSmokeEnd:

;;; The bootstrap uses exactly the same production body as the generated copy.
	include "ass.asm"
