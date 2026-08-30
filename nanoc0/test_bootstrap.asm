	include "../test.inc"

FAIL_OPEN   = $01
FAIL_PARSE  = $02
FAIL_SHAPE  = $03

;;; Parse the actual bootstrap program, not a synthetic stress fixture. This is
;;; the executable proof that the bounded scanner/symbol capacities still cover
;;; the program Phase 1 exists to compile.
	* = $4000

main:
	lda #<bootstrapName
	sta sourceName
	lda #>bootstrapName
	sta sourceName+1
	lda #bootstrapNameEnd-bootstrapName
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn

	;; NC_BSS addresses are only allocated symbolically in this test. $0800 leaves
	;; enough 16-bit address space for ass.c's intentionally large static workspaces.
	lda #$00
	sta bssBase
	lda #$08
	sta bssBase+1

	jsr open_source
	bcs .opened
	lda #FAIL_OPEN
	jmp finish
.opened:
	jsr parse_translation_unit
	bcs .parsed
	lda #FAIL_PARSE
	jmp finish

.parsed:
	lda parserError
	bne .shapeFail
	lda persistentCount
	cmp #129
	bne .shapeFail
	lda userFunctionCount
	cmp #43
	bne .shapeFail
	lda parameterMetaCount
	cmp #105
	bne .shapeFail
	lda persistentNameUsed
	cmp #$fc			; 2044 = $07fc length-prefixed bytes
	bne .shapeFail
	lda persistentNameUsed+1
	cmp #$07
	bne .shapeFail
	lda currentCount
	bne .shapeFail
	lda #TEST_PASS
	jmp finish
.shapeFail:
	lda #FAIL_SHAPE
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; The capacity test cares only that emission can proceed. Static bytes and
;;; storage identities are already tested in test_declarations.asm.
emit_persistent_symbol:
	sec
	rts
emit_current_symbol:
	sec
	rts
emit_static_byte:
	sec
	rts
emit_bss_boundaries:
	sec
	rts

bootstrapName:
	byte 'a','s','s','.','c'
bootstrapNameEnd:

	include "declarations.asm"
