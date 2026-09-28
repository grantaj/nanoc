	include "../test.inc"

NANOC0_IMAGE = $4000

FAIL_COMPILE_SOURCE = $20
FAIL_COMPILE_ASS    = $30

;;; This driver is deliberately only a code-generation development rung.
;;; VASM places the exact production nanoc0 image at $4000 in this same PRG, so
;;; compiler resident size cannot prevent us from exercising the real 6502
;;; compiler. The ordinary integration driver remains the stronger self-host
;;; rung: current ass -> nanoc0 -> C.
INTEGRATION_STAGE  = $03
INTEGRATION_STATUS = $04
INTEGRATION_LINE   = $05
INTEGRATION_DETAIL = $07
INTEGRATION_BSS    = $08
INTEGRATION_EXTRA  = $0a
INTEGRATION_HIDDEN = $0b

STAGE_COMPILE_SOURCE = 2
STAGE_COMPILE_ASS    = 3

	* = $0800

main:
	lda #$00
	sta INTEGRATION_STAGE
	sta INTEGRATION_STATUS
	sta INTEGRATION_LINE
	sta INTEGRATION_LINE+1
	sta INTEGRATION_DETAIL
	sta INTEGRATION_BSS
	sta INTEGRATION_BSS+1
	sta INTEGRATION_EXTRA
	sta INTEGRATION_HIDDEN
	sta INTEGRATION_HIDDEN+1

	;;; Keep one small complete program ahead of bootstrap/ass.c so entry/output
	;;; regressions remain cheap to diagnose.
	lda #<smallSourceName
	sta NANOC_COMMAND_SOURCE
	lda #>smallSourceName
	sta NANOC_COMMAND_SOURCE+1
	lda #smallSourceNameEnd-smallSourceName
	sta NANOC_COMMAND_SOURCE_LENGTH
	lda #<smallOutputName
	sta NANOC_COMMAND_OUTPUT
	lda #>smallOutputName
	sta NANOC_COMMAND_OUTPUT+1
	lda #smallOutputNameEnd-smallOutputName
	sta NANOC_COMMAND_OUTPUT_LENGTH
	lda #STAGE_COMPILE_SOURCE
	sta INTEGRATION_STAGE
	jsr NANOC0_IMAGE
	jsr capture_nanoc_result
	lda NANOC_COMMAND_STATUS
	beq .smallReady
	ora #FAIL_COMPILE_SOURCE
	jmp finish

.smallReady:
	;;; Compile the exact committed bootstrap source with the production 6502
	;;; compiler. Only the assembly of nanoc0 itself has been taken off this rung.
	lda #<assSourceName
	sta NANOC_COMMAND_SOURCE
	lda #>assSourceName
	sta NANOC_COMMAND_SOURCE+1
	lda #assSourceNameEnd-assSourceName
	sta NANOC_COMMAND_SOURCE_LENGTH
	lda #<assOutputName
	sta NANOC_COMMAND_OUTPUT
	lda #>assOutputName
	sta NANOC_COMMAND_OUTPUT+1
	lda #assOutputNameEnd-assOutputName
	sta NANOC_COMMAND_OUTPUT_LENGTH
	lda #STAGE_COMPILE_ASS
	sta INTEGRATION_STAGE
	jsr NANOC0_IMAGE
	jsr capture_nanoc_result
	lda NANOC_COMMAND_STATUS
	beq .pass
	ora #FAIL_COMPILE_ASS
	jmp finish
.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

capture_nanoc_result:
	lda NANOC_COMMAND_STATUS
	sta INTEGRATION_STATUS
	lda NANOC_COMMAND_LINE
	sta INTEGRATION_LINE
	lda NANOC_COMMAND_LINE+1
	sta INTEGRATION_LINE+1
	lda NANOC_COMMAND_DETAIL
	sta INTEGRATION_DETAIL
	lda #$00
	sta INTEGRATION_EXTRA
	sta INTEGRATION_HIDDEN
	sta INTEGRATION_HIDDEN+1
	lda NANOC_COMMAND_BSS_BYTES
	sta INTEGRATION_BSS
	lda NANOC_COMMAND_BSS_BYTES+1
	sta INTEGRATION_BSS+1
	rts

smallSourceName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','S','T','M','T','/','R','E','T','U','R','N','8','.','C'
smallSourceNameEnd:
smallOutputName:
	byte 'N','C','O','U','T','.','A','S','M',',','S',',','W'
smallOutputNameEnd:
assSourceName:
	byte 'B','O','O','T','S','T','R','A','P','/','A','S','S','.','C'
assSourceNameEnd:
assOutputName:
	byte 'A','S','S','F','R','O','M','C','.','A','S','M',',','S',',','W'
assOutputNameEnd:

;;; Exact production compiler. This source sets its own $4000 origin.
	include "nanoc0.asm"
