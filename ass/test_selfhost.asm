	include "../test.inc"

SELF_HOSTED        = $0800
SELFHOST_TEST_ENTRY = $2c00
SMOKE_OUTPUT       = $3400

FAIL_BUILD_B     = $10
FAIL_RUN_B       = $20
FAIL_SMOKE_BYTES = $30

;;; Keep the small proof harness below ass's fixed command/workspace pages, and
;;; keep the vasm-built assembler itself at its production $4000 origin. The
;;; generated $0800 copy ends below this harness; A ends below the $6000 staging
;;; buffer. That separation matters: staging must never overwrite the assembler
;;; that is currently using it.
;;;
;;; Workspace mailbox saved with TEST_RESULT by tests/run-test.sh while the
;;; fixed symbol-table split is being measured. Packed tables need one end
;;; pointer each; usage is simply end minus the fixed table start.
SH_PERSIST_END = $03
SH_LOCAL_END   = $05

	* = SELFHOST_TEST_ENTRY

main:
	;; A is the vasm-built copy at $4000. Use it to assemble the real production
	;; ass source tree into B at $0800.
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
	jsr captureWorkspace
	lda ASSEMBLER_COMMAND_STATUS
	ora #FAIL_BUILD_B
	jmp finish

.builtB:
	;; Capture A's completed production assembly before B reuses the same fixed
	;; work tables. This is diagnostic only and does not affect the proof below.
	jsr captureWorkspace

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
	lda ASSEMBLER_COMMAND_STATUS
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

captureWorkspace:
	lda symbolTableEnd
	sta SH_PERSIST_END
	lda symbolTableEnd+1
	sta SH_PERSIST_END+1
	lda localSymbolTableEnd
	sta SH_LOCAL_END
	lda localSymbolTableEnd+1
	sta SH_LOCAL_END+1
	rts

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

;;; A uses exactly the same production body and origin as build/ass.prg.
	* = ASSEMBLER_TEST_ENTRY
	include "ass.asm"
