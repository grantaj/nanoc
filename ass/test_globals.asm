	include "zp.inc"
	include "../test.inc"

FAIL_FORWARD_GLOBAL  = $01
FAIL_BACKWARD_GLOBAL = $02

OUTPUT      = $2000
SYMBOLS     = $3000
SYMBOLS_END = $3600

	* = TEST_ENTRY

main:
	sei
	jsr setupSymbols
	jsr testForwardGlobal
	bcc finish
	jsr testBackwardGlobal
	bcc finish
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

setupSymbols:
	lda #<SYMBOLS
	sta symbolTableStart
	lda #>SYMBOLS
	sta symbolTableStart+1
	lda #<SYMBOLS_END
	sta symbolTableLimit
	lda #>SYMBOLS_END
	sta symbolTableLimit+1
	rts

;;; A forward global reference is unresolved during pass 1, then found during
;;; pass 2. JSR has only an absolute form, so its size never changes.
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

;;; A backward global reference is already known during pass 1.
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
