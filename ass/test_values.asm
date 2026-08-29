	include "zp.inc"
	include "../test.inc"

FAIL_CONSTANTS    = $01
FAIL_BAD_CONSTANT = $02

OUTPUT      = $2000
SYMBOLS     = $3000
SYMBOLS_END = $3600
STAGING     = $3600
STAGING_END = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	sei
	jsr setupWorkspace
	jsr testConstants
	bcc finish
	jsr testBadConstant
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

;;; Constants are defined before use and feed the deliberately small value
;;; grammar used by instruction operands.
testConstants:
	lda #<constantSource
	sta ZP_PTR1
	lda #>constantSource
	sta ZP_PTR1+1
	lda #<constantSourceEnd
	sta sourceEnd
	lda #>constantSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	ldx #$00
.check:
	lda OUTPUT,x
	cmp constantBytes,x
	bne .fail
	inx
	cpx #constantBytesEnd-constantBytes
	bne .check
	sec
	rts
.fail:
	lda #FAIL_CONSTANTS
	clc
	rts

;;; Constant definitions do not get a dependency pass. A value that is
;;; unresolved when its definition is encountered is an error.
testBadConstant:
	lda #<badConstantSource
	sta ZP_PTR1
	lda #>badConstantSource
	sta ZP_PTR1+1
	lda #<badConstantSourceEnd
	sta sourceEnd
	lda #>badConstantSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_SYMBOL
	beq .ok
	lda #FAIL_BAD_CONSTANT
	clc
	rts
.ok:
	sec
	rts

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

constantSource:
	string "COUNT = 9"
	string "ADDR = $1234"
	string "entry:"
	string "LDX #COUNT+1"
	string "LDA #<ADDR"
	string "LDY #>ADDR"
	string "CMP #'A'-10"
	string "RTS"
constantSourceEnd:
constantBytes:
	byte $a2,$0a
	byte $a9,$34
	byte $a0,$12
	byte $c9,$37
	byte $60
constantBytesEnd:

badConstantSource:
	string "BAD = missing"
	string "entry:"
	string "RTS"
badConstantSourceEnd:
