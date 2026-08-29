	include "zp.inc"
	include "../test.inc"

FAIL_RESOLVED_ASSEMBLE = $01
FAIL_RESOLVED_BYTES    = $02
FAIL_RESOLVED_POINTER  = $03
FAIL_PHASE_ERROR       = $10
FAIL_LOCAL_SCOPE       = $11
FAIL_BAD_CONSTANT      = $12
FAIL_UNDEFINED         = $13
FAIL_BRANCH_RANGE      = $14

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

	jsr testResolvedProgram
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

;;; testResolvedProgram
;;; Exercise constants, global/local forward and backward references, repeated
;;; local names, and the small value forms needed by nanoc source.
testResolvedProgram:
	lda #<resolvedSource
	sta ZP_PTR1
	lda #>resolvedSource
	sta ZP_PTR1+1
	lda #<resolvedSourceEnd
	sta sourceEnd
	lda #>resolvedSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	beq .checkBytes
	;; Temporary diagnostic: $80 | ASSEMBLE_* exposes the exact failing status
	;; through the same native result byte used by every other test.
	ora #$80
	clc
	rts

.checkBytes:
	ldx #$00
.checkByte:
	lda OUTPUT,x
	cmp resolvedBytes,x
	bne .badBytes
	inx
	cpx #resolvedBytesEnd-resolvedBytes
	bne .checkByte
	lda assemblyPtr
	cmp #<(OUTPUT+resolvedBytesEnd-resolvedBytes)
	bne .badPointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+resolvedBytesEnd-resolvedBytes)
	bne .badPointer
	sec
	rts
.badBytes:
	lda #FAIL_RESOLVED_BYTES
	clc
	rts
.badPointer:
	lda #FAIL_RESOLVED_POINTER
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
	include "assembler.asm"

resolvedSource:
	string "COUNT = 9"
	string "ADDR = $1234"
	string "first:"
	string "LDA #<ADDR"
	string "LDX #>ADDR"
	string "LDY #'A'-10"
	string "BNE .done"
	string ".loop:"
	string "INX"
	string "BNE .loop"
	string ".done:"
	string "JSR second"
	string "JMP first"
	string "second:"
	string "LDA ADDR+1"
	string "BNE .done"
	string ".done:"
	string "LDX #COUNT+1"
	string "RTS"
resolvedSourceEnd:

resolvedBytes:
	byte $a9,$34		; LDA #<ADDR
	byte $a2,$12		; LDX #>ADDR
	byte $a0,$37		; LDY #'A'-10
	byte $d0,$03		; BNE first .done
	byte $e8		; INX
	byte $d0,$fd		; BNE first .loop
	byte $20,$11,$20	; JSR second
	byte $4c,$00,$20	; JMP first
	byte $ad,$35,$12	; LDA ADDR+1
	byte $d0,$00		; BNE second .done
	byte $a2,$0a		; LDX #COUNT+1
	byte $60		; RTS
resolvedBytesEnd:

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
