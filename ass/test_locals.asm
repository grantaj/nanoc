	include "zp.inc"
	include "../test.inc"

FAIL_LOCAL_REFERENCES = $01
FAIL_LOCAL_SCOPE      = $02

OUTPUT            = $2000
SYMBOLS           = $3000
SYMBOLS_END       = $3500
LOCAL_SYMBOLS     = $3500
LOCAL_SYMBOLS_END = $3600
STAGING           = $3600
STAGING_END       = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	sei
	jsr setupWorkspace
	jsr testLocalReferences
	bcc finish
	jsr testLocalScopeError
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
	lda #<LOCAL_SYMBOLS
	sta localSymbolTableStart
	lda #>LOCAL_SYMBOLS
	sta localSymbolTableStart+1
	lda #<LOCAL_SYMBOLS_END
	sta localSymbolTableLimit
	lda #>LOCAL_SYMBOLS_END
	sta localSymbolTableLimit+1
	lda #<STAGING
	sta stagingStart
	lda #>STAGING
	sta stagingStart+1
	lda #<STAGING_END
	sta stagingLimit
	lda #>STAGING_END
	sta stagingLimit+1
	rts

;;; Dot names live only until the next global label. The same `.done` spelling is
;;; therefore reused from the rewound local scratch table. `later` is deliberately
;;; referenced before several scope changes to prove global forward names remain
;;; in the persistent table while local tables come and go.
testLocalReferences:
	lda #<localSource
	sta ZP_PTR1
	lda #>localSource
	sta ZP_PTR1+1
	lda #<localSourceEnd
	sta sourceEnd
	lda #>localSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	beq .ok
	lda #FAIL_LOCAL_REFERENCES
	clc
	rts
.ok:
	sec
	rts

;;; A local label before any global label has no scope.
testLocalScopeError:
	lda #<badLocalSource
	sta ZP_PTR1
	lda #>badLocalSource
	sta ZP_PTR1+1
	lda #<badLocalSourceEnd
	sta sourceEnd
	lda #>badLocalSourceEnd
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

	include "parser.asm"
	include "instruction.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

localSource:
	string "first:"
	string "JMP later"
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
	string "later:"
	string "RTS"
localSourceEnd:

badLocalSource:
	string ".bad:"
	string "RTS"
badLocalSourceEnd: