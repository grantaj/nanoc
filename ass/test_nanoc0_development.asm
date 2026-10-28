	include "../test.inc"
	include "../nanoc0/interface.inc"

; Development-only: real nanoc0 executes at $4000 and emits exact nanoc1.c
; with code $4000-$cfff and BSS $0800-$3fff. Do NOT assemble or run that
; image in this process: the resident nanoc0 uses $4000 and $c000 workspace.

	* = $0800
main:
	lda #<sourceName
	sta NANOC_COMMAND_SOURCE
	lda #>sourceName
	sta NANOC_COMMAND_SOURCE+1
	lda #sourceEnd-sourceName
	sta NANOC_COMMAND_SOURCE_LENGTH
	lda #<outputName
	sta NANOC_COMMAND_OUTPUT
	lda #>outputName
	sta NANOC_COMMAND_OUTPUT+1
	lda #outputEnd-outputName
	sta NANOC_COMMAND_OUTPUT_LENGTH
	lda #NANOC_LAYOUT_DEVELOPMENT
	sta NANOC_COMMAND_LAYOUT
	jsr $4000
	lda NANOC_COMMAND_STATUS
	sta $03
	lda NANOC_COMMAND_DETAIL
	sta $04
	lda NANOC_COMMAND_LINE
	sta $07
	lda NANOC_COMMAND_LINE+1
	sta $08
	lda NANOC_COMMAND_BSS_BYTES
	sta $05
	lda NANOC_COMMAND_BSS_BYTES+1
	sta $06
	lda NANOC_COMMAND_STATUS
	bne .failure
	lda #TEST_PASS
	jmp .finish
.failure:
	ora #$40
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

sourceName:
	byte 'N','A','N','O','C','1','/','N','A','N','O','C','1','.','C'
sourceEnd:
outputName:
	byte 'N','A','N','O','C','1','D','E','V','.','A','S','M',',','S',',','W'
outputEnd:
