	include "zp.inc"
	include "../test.inc"

FAIL_FORWARD          = $01
FAIL_UNDEFINED        = $02
FAIL_BRANCH_PLUS_127  = $03
FAIL_BRANCH_MINUS_128 = $04
FAIL_BRANCH_PLUS_128  = $05
FAIL_BRANCH_MINUS_129 = $06
FAIL_ATOMIC_OUTPUT    = $07

OUTPUT                 = $2000
BRANCH_PLUS            = $2200
BRANCH_PLUS_TARGET     = $2281
BRANCH_MINUS           = $2300
BRANCH_MINUS_TARGET    = $2282
BRANCH_TOO_FAR         = $2400
BRANCH_TOO_FAR_TARGET  = $2482
BRANCH_TOO_BACK        = $2500
BRANCH_TOO_BACK_TARGET = $2481
SYMBOLS                = $3000
SYMBOLS_END            = $3600
STAGING                = $3600
STAGING_END            = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	sei
	jsr setupWorkspace
	jsr testForwardReferences
	bcc finish
	jsr testUndefinedSymbol
	bcc finish
	jsr testBranchLimits
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

;;; Exercise the exact signed branch limits through source -> parser -> staged
;;; assembler. The branch byte is target - (branch address + 2).
testBranchLimits:
	;; $2281 - ($2200 + 2) = +127.
	lda #<branchPlus127Source
	sta ZP_PTR1
	lda #>branchPlus127Source
	sta ZP_PTR1+1
	lda #<branchPlus127SourceEnd
	sta sourceEnd
	lda #>branchPlus127SourceEnd
	sta sourceEnd+1
	lda #<BRANCH_PLUS
	sta assemblyPtr
	lda #>BRANCH_PLUS
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .failPlus127
	lda BRANCH_PLUS
	cmp #$d0
	bne .failPlus127
	lda BRANCH_PLUS+1
	cmp #$7f
	bne .failPlus127
	lda assemblyPtr
	cmp #<(BRANCH_PLUS+2)
	bne .failPlus127
	lda assemblyPtr+1
	cmp #>(BRANCH_PLUS+2)
	beq .minus128
.failPlus127:
	lda #FAIL_BRANCH_PLUS_127
	clc
	rts

	;; $2282 - ($2300 + 2) = -128.
.minus128:
	lda #<branchMinus128Source
	sta ZP_PTR1
	lda #>branchMinus128Source
	sta ZP_PTR1+1
	lda #<branchMinus128SourceEnd
	sta sourceEnd
	lda #>branchMinus128SourceEnd
	sta sourceEnd+1
	lda #<BRANCH_MINUS
	sta assemblyPtr
	lda #>BRANCH_MINUS
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .failMinus128
	lda BRANCH_MINUS
	cmp #$d0
	bne .failMinus128
	lda BRANCH_MINUS+1
	cmp #$80
	bne .failMinus128
	lda assemblyPtr
	cmp #<(BRANCH_MINUS+2)
	bne .failMinus128
	lda assemblyPtr+1
	cmp #>(BRANCH_MINUS+2)
	beq .plus128
.failMinus128:
	lda #FAIL_BRANCH_MINUS_128
	clc
	rts

	;; $2482 - ($2400 + 2) = +128: fail before committing anything.
.plus128:
	lda #$5a
	sta BRANCH_TOO_FAR
	lda #$a5
	sta BRANCH_TOO_FAR+1
	lda #<branchPlus128Source
	sta ZP_PTR1
	lda #>branchPlus128Source
	sta ZP_PTR1+1
	lda #<branchPlus128SourceEnd
	sta sourceEnd
	lda #>branchPlus128SourceEnd
	sta sourceEnd+1
	lda #<BRANCH_TOO_FAR
	sta assemblyPtr
	lda #>BRANCH_TOO_FAR
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_EMIT_ERROR
	bne .failPlus128
	lda assemblyPtr
	cmp #<BRANCH_TOO_FAR
	bne .failPlus128
	lda assemblyPtr+1
	cmp #>BRANCH_TOO_FAR
	bne .failPlus128
	lda BRANCH_TOO_FAR
	cmp #$5a
	bne .failPlus128
	lda BRANCH_TOO_FAR+1
	cmp #$a5
	beq .minus129
.failPlus128:
	lda #FAIL_BRANCH_PLUS_128
	clc
	rts

	;; $2481 - ($2500 + 2) = -129: likewise fail atomically.
.minus129:
	lda #$3c
	sta BRANCH_TOO_BACK
	lda #$c3
	sta BRANCH_TOO_BACK+1
	lda #<branchMinus129Source
	sta ZP_PTR1
	lda #>branchMinus129Source
	sta ZP_PTR1+1
	lda #<branchMinus129SourceEnd
	sta sourceEnd
	lda #>branchMinus129SourceEnd
	sta sourceEnd+1
	lda #<BRANCH_TOO_BACK
	sta assemblyPtr
	lda #>BRANCH_TOO_BACK
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_EMIT_ERROR
	bne .failMinus129
	lda assemblyPtr
	cmp #<BRANCH_TOO_BACK
	bne .failMinus129
	lda assemblyPtr+1
	cmp #>BRANCH_TOO_BACK
	bne .failMinus129
	lda BRANCH_TOO_BACK
	cmp #$3c
	bne .failMinus129
	lda BRANCH_TOO_BACK+1
	cmp #$c3
	bne .failMinus129
	sec
	rts
.failMinus129:
	lda #FAIL_BRANCH_MINUS_129
	clc
	rts

	include "parser.asm"
	include "instruction.asm"
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

branchPlus127Source:
	string "TARGET = $2281"
	string "BNE TARGET"
branchPlus127SourceEnd:

branchMinus128Source:
	string "TARGET = $2282"
	string "BNE TARGET"
branchMinus128SourceEnd:

branchPlus128Source:
	string "TARGET = $2482"
	string "BNE TARGET"
branchPlus128SourceEnd:

branchMinus129Source:
	string "TARGET = $2481"
	string "BNE TARGET"
branchMinus129SourceEnd:
