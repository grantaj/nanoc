	include "../test.inc"

FAIL_OPEN   = $01
FAIL_KIND   = $02
FAIL_REASON = $03

;;; Small regression for the zero-length character-literal boundary.  The main
;;; scanner test already covers multi-byte character literals; keeping this case
;;; separate avoids making the malformed-input sequence depend on error recovery.
	* = $8000

main:
	lda #<emptyCharName
	sta sourceName
	lda #>emptyCharName
	sta sourceName+1
	lda #emptyCharNameEnd-emptyCharName
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	jsr open_source
	bcc .openFail

	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_ERROR
	bne .kindFail
	lda scannerError
	cmp #LEX_BAD_CHAR_LENGTH
	bne .reasonFail

	lda #TEST_PASS
	jmp finish
.openFail:
	lda #FAIL_OPEN
	jmp finish
.kindFail:
	lda #FAIL_KIND
	jmp finish
.reasonFail:
	lda #FAIL_REASON
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

emptyCharName:
	byte 'E','M','P','T','Y','C','H','A','R','.','C'
emptyCharNameEnd:

	include "scanner.asm"
