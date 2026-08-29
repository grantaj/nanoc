	include "zp.inc"
	include "../test.inc"

FAIL_RELAX         = $01
FAIL_UNDEFINED     = $02
FAIL_BRANCH_RANGE  = $03
FAIL_MULTI_RELAX   = $04
FAIL_ATOMIC_OUTPUT = $05

OUTPUT       = $2000
RELAX_OUTPUT = $0080
ITER_OUTPUT  = $00f9
SYMBOLS      = $3000
SYMBOLS_END  = $3600
STAGING      = $3600
STAGING_END  = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	;; The relaxation tests use zero-page addresses. Own the machine while they
	;; run rather than letting a KERNAL IRQ use assembler workspace.
	sei
	jsr setupWorkspace
	jsr testRelaxation
	bcc finish
	jsr testMultiRelaxation
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

;;; Pass 1 conservatively stages LDA absolute. Once target is known to be in
;;; zero page, the memory-only layout pass shrinks it and updates target.
testRelaxation:
	lda #<relaxSource
	sta ZP_PTR1
	lda #>relaxSource
	sta ZP_PTR1+1
	lda #<relaxSourceEnd
	sta sourceEnd
	lda #>relaxSourceEnd
	sta sourceEnd+1
	lda #<RELAX_OUTPUT
	sta assemblyPtr
	lda #>RELAX_OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda RELAX_OUTPUT
	cmp #$a5			; LDA zero page
	bne .fail
	lda RELAX_OUTPUT+1
	cmp #$82			; target moved from $0083 to $0082
	bne .fail
	lda RELAX_OUTPUT+2
	cmp #$60
	bne .fail
	lda assemblyPtr
	cmp #$83
	bne .fail
	lda assemblyPtr+1
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_RELAX
	clc
	rts

;;; The second LDA can shrink immediately because low is conservatively $00ff.
;;; That moves near from $0100 to $00ff, enabling the first LDA only on the next
;;; layout walk. After convergence low is $00fd and near is $00fe.
;;;
;;; This test deliberately stops before copyRepresentation: the address range
;;; needed to exercise the $0100 boundary includes $fc-$ff, which are the
;;; assembler's live zero-page pointers. The thing under test here is the
;;; memory-only convergence itself; testRelaxation above already covers commit.
testMultiRelaxation:
	lda #<multiSource
	sta ZP_PTR1
	lda #>multiSource
	sta ZP_PTR1+1
	lda #<multiSourceEnd
	sta sourceEnd
	lda #>multiSourceEnd
	sta sourceEnd+1
	lda #<ITER_OUTPUT
	sta assemblyPtr
	lda #>ITER_OUTPUT
	sta assemblyPtr+1
	lda #$00
	sta sourceFileMode
	jsr beginAssembly
.source:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .layout
	jsr processStatement
	cmp #ASSEMBLE_OK
	bne .fail
	jmp .source
.layout:
	jsr sealRepresentation
	jsr allLabelsDefined
	bcc .fail
	jsr relaxLayout
	cmp #ASSEMBLE_OK
	bne .fail
	jsr resolveAllHoles
	cmp #ASSEMBLE_OK
	bne .fail

	;; Staging remains conservative-width. Both direct records must nevertheless
	;; contain their final short opcodes and operands after convergence.
	lda STAGING
	cmp #$a5
	bne .fail
	lda STAGING+1
	cmp #$fe			; near
	bne .fail
	lda STAGING+3
	cmp #$a5
	bne .fail
	lda STAGING+4
	cmp #$fd			; low
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_MULTI_RELAX
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

;;; Branch displacement is computed from final relaxed addresses. A range error
;;; is detected while staging is still private, before target memory is changed.
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

relaxSource:
	string "entry:"
	string "LDA target"
	string "target:"
	string "RTS"
relaxSourceEnd:

multiSource:
	string "LDA near"
	string "LDA low"
	string "low:"
	string "RTS"
	string "near:"
	string "RTS"
multiSourceEnd:

undefinedSource:
	string "entry:"
	string "JMP missing"
undefinedSourceEnd:

branchRangeSource:
	string "FAR = $3000"
	string "entry:"
	string "BNE FAR"
branchRangeSourceEnd:
