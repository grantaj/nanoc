	include "zp.inc"
	include "../test.inc"

FAIL_DATA_BYTES   = $01
FAIL_DATA_POINTER = $02
FAIL_PAGE_CROSS   = $03
FAIL_BYTE_RANGE   = $04
FAIL_BAD_LIST     = $05
FAIL_BAD_ORIGIN   = $06
FAIL_LATE_ORIGIN  = $07
FAIL_LABEL_ORIGIN = $08

OUTPUT      = $2100
PAGE_OUTPUT = $20ff
SYMBOLS     = $3000
SYMBOLS_END = $3600
STAGING     = $3600
STAGING_END = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	jsr setupWorkspace
	jsr testDataBytes
	bcc finish
	jsr testPageCrossing
	bcc finish
	jsr testByteRange
	bcc finish
	jsr testBadList
	bcc finish
	jsr testBadOrigin
	bcc finish
	jsr testLateOrigin
	bcc finish
	jsr testLabelThenOrigin
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

;;; Origin, byte, word, spaces around commas, character values, and forward
;;; labels all reduce directly to final-size staged bytes plus only the unresolved
;;; reference state that is still needed.
testDataBytes:
	lda #<dataSource
	sta ZP_PTR1
	lda #>dataSource
	sta ZP_PTR1+1
	lda #<dataSourceEnd
	sta sourceEnd
	lda #>dataSourceEnd
	sta sourceEnd+1
	lda #$00
	sta assemblyPtr
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .failBytes

	ldx #$00
.check:
	lda OUTPUT,x
	cmp expectedData,x
	bne .failBytes
	inx
	cpx #expectedDataEnd-expectedData
	bne .check

	lda assemblyPtr
	cmp #<(OUTPUT+5)
	bne .failPointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+5)
	bne .failPointer
	sec
	rts
.failBytes:
	lda #FAIL_DATA_BYTES
	clc
	rts
.failPointer:
	lda #FAIL_DATA_POINTER
	clc
	rts

;;; Final copy naturally crosses a destination page boundary.
testPageCrossing:
	lda #<pageSource
	sta ZP_PTR1
	lda #>pageSource
	sta ZP_PTR1+1
	lda #<pageSourceEnd
	sta sourceEnd
	lda #>pageSourceEnd
	sta sourceEnd+1
	lda #$00
	sta assemblyPtr
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda PAGE_OUTPUT
	cmp #$aa
	bne .fail
	lda PAGE_OUTPUT+1
	cmp #$bb
	bne .fail
	lda assemblyPtr
	cmp #$01
	bne .fail
	lda assemblyPtr+1
	cmp #$21
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_PAGE_CROSS
	clc
	rts

;;; byte is deliberately a byte declaration, not truncating word storage.
testByteRange:
	lda #<rangeSource
	sta ZP_PTR1
	lda #>rangeSource
	sta ZP_PTR1+1
	lda #<rangeSourceEnd
	sta sourceEnd
	lda #>rangeSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_DATA
	beq .ok
	lda #FAIL_BYTE_RANGE
	clc
	rts
.ok:
	sec
	rts

;;; Empty items and trailing commas are syntax errors, not zero values.
testBadList:
	lda #<badListSource
	sta ZP_PTR1
	lda #>badListSource
	sta ZP_PTR1+1
	lda #<badListSourceEnd
	sta sourceEnd
	lda #>badListSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_DATA
	beq .ok
	lda #FAIL_BAD_LIST
	clc
	rts
.ok:
	sec
	rts

;;; Origin must be known when encountered; there is no deferred-origin state.
testBadOrigin:
	lda #<badOriginSource
	sta ZP_PTR1
	lda #>badOriginSource
	sta ZP_PTR1+1
	lda #<badOriginSourceEnd
	sta sourceEnd
	lda #>badOriginSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_ORIGIN
	beq .ok
	lda #FAIL_BAD_ORIGIN
	clc
	rts
.ok:
	sec
	rts

;;; There is exactly one origin position: constants may precede it, but an
;;; origin after code/data is rejected rather than creating segmented output.
testLateOrigin:
	lda #<lateOriginSource
	sta ZP_PTR1
	lda #>lateOriginSource
	sta ZP_PTR1+1
	lda #<lateOriginSourceEnd
	sta sourceEnd
	lda #>lateOriginSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_ORIGIN
	beq .ok
	lda #FAIL_LATE_ORIGIN
	clc
	rts
.ok:
	sec
	rts

;;; A label fixes an address just as code/data does, so it also closes the one
;;; origin position before any later `* = value` can move assemblyPtr.
testLabelThenOrigin:
	lda #<labelOriginSource
	sta ZP_PTR1
	lda #>labelOriginSource
	sta ZP_PTR1+1
	lda #<labelOriginSourceEnd
	sta sourceEnd
	lda #>labelOriginSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_ORIGIN
	beq .ok
	lda #FAIL_LABEL_ORIGIN
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

dataSource:
	string "* = $2100"
	string "byte <later, >later"
	string "word later"
	string "later:"
	string "byte 'A'"
dataSourceEnd:

expectedData:
	byte $04,$21			; low/high bytes of later = $2104
	byte $04,$21			; word later, little endian
	byte 'A'
expectedDataEnd:

pageSource:
	string "* = $20ff"
	string "byte $aa, $bb"
pageSourceEnd:

rangeSource:
	string "byte $1234"
rangeSourceEnd:

badListSource:
	string "byte 1,"
badListSourceEnd:

badOriginSource:
	string "* = missing"
badOriginSourceEnd:

lateOriginSource:
	string "LDA target"
	string "* = $0080"
	string "target:"
	string "RTS"
lateOriginSourceEnd:

labelOriginSource:
	string "oldPlace:"
	string "* = $2000"
labelOriginSourceEnd:
