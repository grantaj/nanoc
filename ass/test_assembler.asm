	include "zp.inc"
	include "../test.inc"

FAIL_CONSTANTS       = $01
FAIL_LOCAL_SCOPES    = $02
FAIL_FORWARD_GLOBAL  = $03
FAIL_BACKWARD_GLOBAL = $04
FAIL_PHASE_ERROR     = $10
FAIL_LOCAL_SCOPE     = $11
FAIL_BAD_CONSTANT    = $12
FAIL_UNDEFINED       = $13
FAIL_BRANCH_RANGE    = $14

OUTPUT       = $2000
PHASE_OUTPUT = $0080
SYMBOLS      = $3000
SYMBOLS_END  = $3600

	* = TEST_ENTRY

main:
	;; The phase-error case deliberately emits into zero page. Own the machine
	;; while doing that rather than letting a KERNAL IRQ use overwritten state.
	sei

	lda #<SYMBOLS
	sta symbolTableStart
	lda #>SYMBOLS
	sta symbolTableStart+1
	lda #<SYMBOLS_END
	sta symbolTableLimit
	lda #>SYMBOLS_END
	sta symbolTableLimit+1

	jsr testConstants
	bcc finish
	jsr testLocalScopes
	bcc finish
	jsr testForwardGlobal
	bcc finish
	jsr testBackwardGlobal
	bcc finish
	jsr testPhaseError
	bcc finish
	jsr testLocalScopeError
	bcc finish
	jsr testBadConstant
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

;;; Constants are defined before use and may feed the deliberately small value
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

;;; Local names use the most recent global label as their scope. This exercises
;;; a backward local reference and reuses `.done` in a second scope.
testLocalScopes:
	lda #<localScopesSource
	sta ZP_PTR1
	lda #>localScopesSource
	sta ZP_PTR1+1
	lda #<localScopesSourceEnd
	sta sourceEnd
	lda #>localScopesSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	beq .ok
	lda #FAIL_LOCAL_SCOPES
	clc
	rts
.ok:
	sec
	rts

;;; A forward global reference is simply unresolved during pass 1, then found
;;; in the symbol table during pass 2.
testForwardGlobal:
	lda #<forwardGlobalSource
	sta ZP_PTR1
	lda #>forwardGlobalSource
	sta ZP_PTR1+1
	lda #<forwardGlobalSourceEnd
	sta sourceEnd
	lda #>forwardGlobalSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda OUTPUT
	cmp #$20			; JSR absolute
	bne .fail
	lda OUTPUT+1
	cmp #$03
	bne .fail
	lda OUTPUT+2
	cmp #$20
	bne .fail
	lda OUTPUT+3
	cmp #$60			; RTS
	bne .fail
	lda assemblyPtr
	cmp #<(OUTPUT+4)
	bne .fail
	lda assemblyPtr+1
	cmp #>(OUTPUT+4)
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_FORWARD_GLOBAL
	clc
	rts

;;; A backward global reference is already known during pass 1 and remains a
;;; normal absolute instruction in pass 2.
testBackwardGlobal:
	lda #<backwardGlobalSource
	sta ZP_PTR1
	lda #>backwardGlobalSource
	sta ZP_PTR1+1
	lda #<backwardGlobalSourceEnd
	sta sourceEnd
	lda #>backwardGlobalSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda OUTPUT
	cmp #$4c			; JMP absolute
	bne .fail
	lda OUTPUT+1
	cmp #$00
	bne .fail
	lda OUTPUT+2
	cmp #$20
	bne .fail
	lda assemblyPtr
	cmp #<(OUTPUT+3)
	bne .fail
	lda assemblyPtr+1
	cmp #>(OUTPUT+3)
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_BACKWARD_GLOBAL
	clc
	rts

;;; A forward direct reference below $0100 shrinks on pass 2. We deliberately
;;; reject that layout change rather than adding relaxation passes.
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

;;; A local label has no meaning until a global label has opened a scope.
testLocalScopeError:
	lda #<localScopeSource
	sta ZP_PTR1
	lda #>localScopeSource
	sta ZP_PTR1+1
	lda #<localScopeSourceEnd
	sta sourceEnd
	lda #>localScopeSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_SCOPE_ERROR
	beq .ok
	lda #FAIL_LOCAL_SCOPE
	clc
	rts
.ok:
	sec
	rts

;;; Constant definitions are intentionally simpler than labels: their value
;;; must already be resolvable on pass 1.
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

;;; An instruction may carry a forward reference through pass 1, but it must
;;; exist by pass 2.
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

constantSource:
	string "COUNT = 9"
	string "ADDR = $1234"
	string "entry:"
	string "LDX #COUNT+1"
	string "LDA #<ADDR"
	string "LDY #'A'-10"
	string "RTS"
constantSourceEnd:
constantBytes:
	byte $a2,$0a
	byte $a9,$34
	byte $a0,$37
	byte $60
constantBytesEnd:

localScopesSource:
	string "first:"
	string ".loop:"
	string "INX"
	string "BNE .loop"
	string "BNE .done"
	string ".done:"
	string "RTS"
	string "second:"
	string "BNE .done"
	string ".done:"
	string "RTS"
localScopesSourceEnd:

forwardGlobalSource:
	string "first:"
	string "JSR second"
	string "second:"
	string "RTS"
forwardGlobalSourceEnd:

backwardGlobalSource:
	string "first:"
	string "JMP first"
backwardGlobalSourceEnd:

phaseSource:
	string "entry:"
	string "LDA target"
	string "target:"
	string "RTS"
phaseSourceEnd:

localScopeSource:
	string ".bad:"
	string "RTS"
localScopeSourceEnd:

badConstantSource:
	string "BAD = missing"
	string "entry:"
	string "RTS"
badConstantSourceEnd:

undefinedSource:
	string "entry:"
	string "JMP missing"
undefinedSourceEnd:

branchRangeSource:
	string "FAR = $3000"
	string "entry:"
	string "BNE FAR"
branchRangeSourceEnd:
