	include "zp.inc"
	include "../test.inc"

FAIL_STREAM_STATUS  = $01
FAIL_STREAM_BYTES   = $02
FAIL_STREAM_POINTER = $03

OUTPUT            = $2200
LINE_BUFFER       = $2600
SYMBOLS           = $2700
SYMBOLS_END       = $2e00
LOCAL_SYMBOLS     = $2e00
LOCAL_SYMBOLS_END = $3000
STAGING           = $3000
STAGING_END       = $4000

	* = ASSEMBLER_TEST_ENTRY

main:
	jsr setupWorkspace
	lda #<rootName
	sta sourceName
	lda #>rootName
	sta sourceName+1
	lda #rootNameEnd-rootName
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #<LINE_BUFFER
	sta sourceLineBuffer
	lda #>LINE_BUFFER
	sta sourceLineBuffer+1
	lda #<OUTPUT
	sta assemblyPtr
	lda #>OUTPUT
	sta assemblyPtr+1
	jsr assembleFile
	cmp #ASSEMBLE_OK
	bne .status

	ldx #$00
.check:
	lda OUTPUT,x
	cmp expected,x
	bne .bytes
	inx
	cpx #expectedEnd-expected
	bne .check
	lda assemblyPtr
	cmp #<(OUTPUT+expectedEnd-expected)
	bne .pointer
	lda assemblyPtr+1
	cmp #>(OUTPUT+expectedEnd-expected)
	bne .pointer
	lda #TEST_PASS
	jmp finish
.status:
	lda #FAIL_STREAM_STATUS
	jmp finish
.bytes:
	lda #FAIL_STREAM_BYTES
	jmp finish
.pointer:
	lda #FAIL_STREAM_POINTER
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

	include "parser.asm"
	include "instruction.asm"
	include "symbols.asm"
	include "value.asm"
	include "assembler.asm"

rootName:
	byte 'M','A','I','N','.','A','S','M'
rootNameEnd:

;;; CHILD.ASM is processed at the include site, so child precedes start.
expected:
	byte $a9,$11,$60		; child: LDA #NEST / RTS
	byte $a9,$2a			; start: LDA #CONST
	byte $20,$00,$22		; JSR child
	byte $60
expectedEnd: