	include "zp.inc"
	include "../test.inc"

FAIL_STRING_ASSEMBLE = $01
FAIL_STRING_BYTES    = $02
FAIL_STRING_POINTER  = $03
FAIL_EMPTY_STRING    = $04
FAIL_BAD_STRING      = $05
FAIL_STRING_PAGE     = $06

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

;;; string copies its literal bytes and appends one NUL, matching the vasm form
;;; already used to build nanoc's in-memory source lines.
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
	bne .failAssemble
	lda OUTPUT
	cmp #'A'
	bne .failBytes
	lda OUTPUT+1
	cmp #'B'
	bne .failBytes
	lda OUTPUT+2
	cmp #'C'
	bne .failBytes
	lda OUTPUT+3
	bne .failBytes
	lda assemblyPtr
	cmp #<(OUTPUT+4)
	bne .failPointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+4)
	bne .failPointer
	sec
	rts
.failAssemble:
	lda #FAIL_STRING_ASSEMBLE
	clc
	rts
.failBytes:
	lda #FAIL_STRING_BYTES
	clc
	rts
.failPointer:
	lda #FAIL_STRING_POINTER
	clc
	rts

;;; An empty literal still emits its NUL byte.
testEmptyString:
	lda #$ff
	sta OUTPUT
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
	lda OUTPUT
	bne .fail
	lda assemblyPtr
	cmp #<(OUTPUT+1)
	bne .fail
	lda assemblyPtr+1
	cmp #>(OUTPUT+1)
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

;;; The terminator crosses the page along with the literal bytes.
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
	lda PAGE_OUTPUT+2
	bne .fail
	lda assemblyPtr
	cmp #$02
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

;;; Build the source lines with byte so the host vasm `string` directive does
;;; not insert its own terminator before our embedded quotes.
stringSource:
	byte 's','t','r','i','n','g',' ',34,'A','B','C',34,0
stringSourceEnd:

emptySource:
	byte 's','t','r','i','n','g',' ',34,34,0
emptySourceEnd:

badStringSource:
	byte 's','t','r','i','n','g',' ',34,'A','B','C',0
badStringSourceEnd:

pageStringSource:
	byte 's','t','r','i','n','g',' ',34,'X','Y',34,0
pageStringSourceEnd:
