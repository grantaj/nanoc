	include "zp.inc"
	include "../test.inc"

FAIL_FORWARD       = $01
FAIL_UNDEFINED     = $02
FAIL_BRANCH_RANGE  = $03
FAIL_ATOMIC_OUTPUT = $04

OUTPUT       = $2000
SYMBOLS      = $3000
SYMBOLS_END  = $3600
STAGING      = $3600
STAGING_END  = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	sei
	jsr setupWorkspace
	jsr testForwardReferences
	bcc finish
	jsr testUndefinedSymbol
	bcc finish
	jsr testBranchRange
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

;;; Constants choose zero-page addressing immediately. Forward labels use final
;;; absolute width, and multiple plain word references to one undefined label are
;;; chained through their own operand bytes until that label appears.
testForwardReferences:
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
	ldx #$00
.check:
	lda OUTPUT,x
	cmp forwardBytes,x
	bne .fail
	inx
	cpx #forwardBytesEnd-forwardBytes
	bne .check
	lda assemblyPtr
	cmp #$09
	bne .fail
	lda assemblyPtr+1
	cmp #$20
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_FORWARD
	clc
	rts

;;; Undefined symbols fail after source has been consumed and before the staged
;;; image is committed to target memory.
testUndefinedSymbol:
	lda #$5a
	sta OUTPUT
	sta OUTPUT+1
	sta OUTPUT+2
	lda #<undefinedSource
	sta ZP_PTR1
	lda #>undefinedSource
	sta ZP_PTR1+1
	lda #<undefinedSourceEnd
	sta sourceEnd
	lda #>undefinedSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_UNDEFINED
	bne .fail
	lda OUTPUT
	cmp #$5a
	bne .atomic
	lda OUTPUT+1
	cmp #$5a
	bne .atomic
	lda OUTPUT+2
	cmp #$5a
	bne .atomic
	sec
	rts
.atomic:
	lda #FAIL_ATOMIC_OUTPUT
	clc
	rts
.fail:
	lda #FAIL_UNDEFINED
	clc
	rts

;;; A fixed branch target is range-checked immediately. A range error still
;;; occurs while staging is private, before target memory is changed.
testBranchRange:
	lda #$69
	sta OUTPUT
	sta OUTPUT+1
	lda #<branchRangeSource
	sta ZP_PTR1
	lda #>branchRangeSource
	sta ZP_PTR1+1
	lda #<branchRangeSourceEnd
	sta sourceEnd
	lda #>branchRangeSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_EMIT_ERROR
	bne .fail
	lda OUTPUT
	cmp #$69
	bne .atomic
	lda OUTPUT+1
	cmp #$69
	bne .atomic
	sec
	rts
.atomic:
	lda #FAIL_ATOMIC_OUTPUT
	clc
	rts
.fail:
	lda #FAIL_BRANCH_RANGE
	clc
	rts

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

forwardSource:
	string "PTR = $fc"
	string "entry:"
	string "LDA PTR"
	string "LDA target"
	string "JMP target"
	string "target:"
	string "RTS"
forwardSourceEnd:
forwardBytes:
	byte $a5,$fc
	byte $ad,$08,$20
	byte $4c,$08,$20
	byte $60
forwardBytesEnd:

undefinedSource:
	string "entry:"
	string "JMP missing"
undefinedSourceEnd:

branchRangeSource:
	string "FAR = $3000"
	string "entry:"
	string "BNE FAR"
branchRangeSourceEnd:
