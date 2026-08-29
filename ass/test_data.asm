	include "zp.inc"
	include "../test.inc"

FAIL_DATA_BYTES   = $01
FAIL_DATA_POINTER = $02
FAIL_PAGE_CROSS   = $03
FAIL_BYTE_RANGE   = $04
FAIL_BAD_LIST     = $05
FAIL_BAD_ORIGIN   = $06
FAIL_LATE_ORIGIN  = $07

OUTPUT      = $2100
PAGE_OUTPUT = $20ff
SYMBOLS     = $3000
SYMBOLS_END = $3600

	* = ASSEMBLER_TEST_ENTRY

main:
	jsr setupSymbols
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

;;; Origin, byte, word, spaces around commas, character values, and forward
;;; labels all use the ordinary two-pass path.
testDataBytes:
	lda #<dataSource
	sta ZP_PTR1
	lda #>dataSource
	sta ZP_PTR1+1
	lda #<dataSourceEnd
	sta sourceEnd
	lda #>dataSourceEnd
	sta sourceEnd+1
	lda #$00			; source origin should replace this initial address
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

;;; Direct data writes naturally cross a destination page boundary.
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

;;; Origin must be known when encountered; it does not get fixup machinery.
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

;;; Pass 1 reserves three bytes for LDA target; pass 2 would prefer two because
;;; target is in zero page. A later origin would erase that size difference, so
;;; reject the origin instead of adding per-origin phase records.
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

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"
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
