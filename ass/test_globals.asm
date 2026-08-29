	include "zp.inc"
	include "../test.inc"

FAIL_FORWARD_GLOBAL  = $01
FAIL_BACKWARD_GLOBAL = $02

OUTPUT      = $2000
SYMBOLS     = $3000
SYMBOLS_END = $3600
STAGING     = $3600
STAGING_END = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	sei
	jsr setupWorkspace
	jsr testForwardGlobal
	bcc finish
	jsr testBackwardGlobal
	bcc finish
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

setupWorkspace:
	lda #<SYMBOLS
	sta symbolTableStart
	lda #>SYMBOLS
	sta symbolTableStart+1
	lda #<SYMBOLS_END
	sta symbolTableLimit
	lda #>SYMBOLS_END
	sta symbolTableLimit+1
	lda #<STAGING
	sta stagingStart
	lda #>STAGING
	sta stagingStart+1
	lda #<STAGING_END
	sta stagingLimit
	lda #>STAGING_END
	sta stagingLimit+1
	rts

;;; A forward global reference becomes a fixed-width word hole. JSR has only an
;;; absolute form, so layout never depends on the eventual value.
testForwardGlobal:
	lda #<forwardSource
	sta ZP_PTR1
	lda #>forwardSource
	sta ZP_PTR1+1
	lda #<forwardSourceEnd
	sta sourceEnd
	lda #>forwardSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda OUTPUT
	cmp #$20
	bne .fail
	lda OUTPUT+1
	cmp #$03
	bne .fail
	lda OUTPUT+2
	cmp #$20
	bne .fail
	lda OUTPUT+3
	cmp #$60
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_FORWARD_GLOBAL
	clc
	rts

;;; Backward label-dependent values are also retained as holes because an
;;; earlier relaxation could still move the label after its line was consumed.
testBackwardGlobal:
	lda #<backwardSource
	sta ZP_PTR1
	lda #>backwardSource
	sta ZP_PTR1+1
	lda #<backwardSourceEnd
	sta sourceEnd
	lda #>backwardSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda OUTPUT
	cmp #$4c
	bne .fail
	lda OUTPUT+1
	cmp #$00
	bne .fail
	lda OUTPUT+2
	cmp #$20
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_BACKWARD_GLOBAL
	clc
	rts

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

forwardSource:
	string "first:"
	string "JSR second"
	string "second:"
	string "RTS"
forwardSourceEnd:

backwardSource:
	string "first:"
	string "JMP first"
backwardSourceEnd:
