	include "../test.inc"

FAIL_OPEN   = $01
FAIL_PARSE  = $02
FAIL_SHAPE  = $03

;;; Parse the actual bootstrap program, not a synthetic stress fixture. This is
;;; the executable proof that the bounded scanner/symbol capacities still cover
;;; the program Phase 1 exists to compile.
;;;
;;; A parse failure returns a compact diagnostic in TEST_RESULT:
;;;   $20 | parserError
;;;   $40 | scannerError when the parser failure came from the scanner
;;; This keeps the native test self-describing while #54 is exercised against
;;; the much larger real bootstrap source.
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
	lda parserError
	cmp #PARSE_SCANNER_ERROR
	bne .parserFailure
	lda scannerError
	ora #$40
	jmp finish
.parserFailure:
	lda parserError
	ora #$20
	jmp finish

.parsed:
	lda parserError
	bne .shapeFail
	lda persistentCount
	cmp #130
	bne .shapeFail
	lda userFunctionCount
	cmp #44
	bne .shapeFail
	lda parameterMetaCount
	cmp #105
	bne .shapeFail
	lda persistentNameUsed
	cmp #$08			; 2056 = $0808 length-prefixed bytes
	bne .shapeFail
	lda persistentNameUsed+1
	cmp #$08
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
	byte 'A','S','S','.','C'
bootstrapNameEnd:

	include "declarations.asm"
