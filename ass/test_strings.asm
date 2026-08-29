	include "zp.inc"
	include "../test.inc"

FAIL_STRING_BYTES   = $01
FAIL_STRING_POINTER = $02
FAIL_EMPTY_STRING   = $03
FAIL_BAD_STRING     = $04
FAIL_STRING_PAGE    = $05

OUTPUT      = $2200
PAGE_OUTPUT = $20ff
SYMBOLS     = $3000
SYMBOLS_END = $3600

	* = ASSEMBLER_TEST_ENTRY

main:
	jsr setupSymbols
	jsr testStringBytes
	bcc finish
	jsr testEmptyString
	bcc finish
	jsr testBadString
	bcc finish
	jsr testStringPageCrossing
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

;;; string copies exactly the bytes inside its quotes and adds no terminator.
testStringBytes:
	lda #<stringSource
	sta ZP_PTR1
	lda #>stringSource
	sta ZP_PTR1+1
	lda #<stringSourceEnd
	sta sourceEnd
	lda #>stringSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .failBytes
	lda OUTPUT
	cmp #'A'
	bne .failBytes
	lda OUTPUT+1
	cmp #'B'
	bne .failBytes
	lda OUTPUT+2
	cmp #'C'
	bne .failBytes
	lda assemblyPtr
	cmp #<(OUTPUT+3)
	bne .failPointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+3)
	bne .failPointer
	sec
	rts
.failBytes:
	lda #FAIL_STRING_BYTES
	clc
	rts
.failPointer:
	lda #FAIL_STRING_POINTER
	clc
	rts

;;; An empty literal is valid and emits no bytes.
testEmptyString:
	lda #<emptySource
	sta ZP_PTR1
	lda #>emptySource
	sta ZP_PTR1+1
	lda #<emptySourceEnd
	sta sourceEnd
	lda #>emptySourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda assemblyPtr
	cmp #<OUTPUT
	bne .fail
	lda assemblyPtr+1
	cmp #>OUTPUT
	bne .fail
	sec
	rts
.fail:
	lda #FAIL_EMPTY_STRING
	clc
	rts

;;; A missing closing quote is a data error.
testBadString:
	lda #<badStringSource
	sta ZP_PTR1
	lda #>badStringSource
	sta ZP_PTR1+1
	lda #<badStringSourceEnd
	sta sourceEnd
	lda #>badStringSourceEnd
	sta sourceEnd+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_BAD_DATA
	beq .ok
	lda #FAIL_BAD_STRING
	clc
	rts
.ok:
	sec
	rts

;;; Literal copying uses assemblyPtr directly and crosses pages normally.
testStringPageCrossing:
	lda #<pageStringSource
	sta ZP_PTR1
	lda #>pageStringSource
	sta ZP_PTR1+1
	lda #<pageStringSourceEnd
	sta sourceEnd
	lda #>pageStringSourceEnd
	sta sourceEnd+1
	lda #<PAGE_OUTPUT
	sta assemblyPtr
	lda #>PAGE_OUTPUT
	sta assemblyPtr+1
	jsr assemble
	cmp #ASSEMBLE_OK
	bne .fail
	lda PAGE_OUTPUT
	cmp #'X'
	bne .fail
	lda PAGE_OUTPUT+1
	cmp #'Y'
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
	lda #FAIL_STRING_PAGE
	clc
	rts

	include "parser.asm"
	include "instruction.asm"
	include "emitter.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

;;; Build source lines explicitly so the fixture itself does not depend on a
;;; host-assembler escape syntax for embedded double quotes.
stringSource:
	string "string "
	byte 34
	string "ABC"
	byte 34,0
stringSourceEnd:

emptySource:
	string "string "
	byte 34,34,0
emptySourceEnd:

badStringSource:
	string "string "
	byte 34
	string "ABC"
	byte 0
badStringSourceEnd:

pageStringSource:
	string "string "
	byte 34
	string "XY"
	byte 34,0
pageStringSourceEnd:
