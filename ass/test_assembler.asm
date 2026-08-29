	include "zp.inc"
	include "../test.inc"

FAIL_PHASE_ERROR  = $01
FAIL_UNDEFINED    = $02
FAIL_BRANCH_RANGE = $03

OUTPUT       = $2000
PHASE_OUTPUT = $0080
SYMBOLS      = $3000
SYMBOLS_END  = $3600

	* = ASSEMBLER_TEST_ENTRY

main:
	;; The phase test deliberately emits into zero page, so own the machine while
	;; this test runs rather than letting a KERNAL IRQ use overwritten workspace.
	sei
	jsr setupSymbols
	jsr testPhaseError
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

;;; A forward direct reference below $0100 shrinks on pass 2. Reject that
;;; layout change rather than inventing relaxation passes.
testPhaseError:
	lda #<phaseSource
	sta ZP_PTR1
	lda #>phaseSource
	sta ZP_PTR1+1
	lda #<phaseSourceEnd
	sta sourceEnd
	lda #>phaseSourceEnd
	sta sourceEnd+1
	lda #<PHASE_OUTPUT
	sta assemblyPtr
	lda #>PHASE_OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_PHASE_ERROR
	beq .ok
	lda #FAIL_PHASE_ERROR
	clc
	rts
.ok:
	sec
	rts

;;; A forward reference may survive pass 1, but it must exist by pass 2.
testUndefinedSymbol:
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
	beq .ok
	lda #FAIL_UNDEFINED
	clc
	rts
.ok:
	sec
	rts

;;; Resolved branches still use emitInstruction's signed-range check.
testBranchRange:
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
	beq .ok
	lda #FAIL_BRANCH_RANGE
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

phaseSource:
	string "entry:"
	string "LDA target"
	string "target:"
	string "RTS"
phaseSourceEnd:

undefinedSource:
	string "entry:"
	string "JMP missing"
undefinedSourceEnd:

branchRangeSource:
	string "FAR = $3000"
	string "entry:"
	string "BNE FAR"
branchRangeSourceEnd:
