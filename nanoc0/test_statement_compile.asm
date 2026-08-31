	include "../test.inc"

ST_OUTPUT_LFN    = 3
ST_OUTPUT_DEVICE = 9

ST_FAIL_UNDECLARED = $01
ST_FAIL_BREAK      = $02
ST_FAIL_DEPTH      = $03
ST_FAIL_LATE       = $04
ST_FAIL_GOTO       = $05
ST_FAIL_CONTINUE   = $06
ST_FAIL_FOR        = $07
ST_FAIL_SWITCH     = $08
ST_FAIL_LABEL      = $09
ST_FAIL_RETURN     = $0a
ST_FAIL_BRACES     = $0b
ST_FAIL_OPEN       = $0c
ST_FAIL_OUTPUT     = $0d

	* = $4000

main:
	jsr st_test_failures
	bcs .return8
	jmp st_finish
.return8:
	lda #returnOutputNameEnd-returnOutputName
	ldx #<returnOutputName
	ldy #>returnOutputName
	jsr st_set_output_name
	lda #returnNameEnd-returnName
	ldx #<returnName
	ldy #>returnName
	jsr st_compile_fixture
	bcs .statements
	jmp st_finish
.statements:
	lda #statementOutputNameEnd-statementOutputName
	ldx #<statementOutputName
	ldy #>statementOutputName
	jsr st_set_output_name
	lda #statementNameEnd-statementName
	ldx #<statementName
	ldy #>statementName
	jsr st_compile_fixture
	bcs .pass
	jmp st_finish
.pass:
	lda #TEST_PASS
st_finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; Negative fixtures are parsed by the production parser with output disabled.
;;; Each one proves a source-language boundary, not a private helper contract.
st_test_failures:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	lda #ST_FAIL_UNDECLARED
	sta stFailureCode
	lda #undeclaredNameEnd-undeclaredName
	ldx #<undeclaredName
	ldy #>undeclaredName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_BREAK_OUTSIDE_LOOP
	sta stExpectedParser
	lda #ST_FAIL_BREAK
	sta stFailureCode
	lda #breakNameEnd-breakName
	ldx #<breakName
	ldy #>breakName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_CONTROL_OVERFLOW
	sta stExpectedParser
	lda #ST_FAIL_DEPTH
	sta stFailureCode
	lda #depthNameEnd-depthName
	ldx #<depthName
	ldy #>depthName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_LATE_LOCAL
	sta stExpectedParser
	lda #ST_FAIL_LATE
	sta stFailureCode
	lda #lateNameEnd-lateName
	ldx #<lateName
	ldy #>lateName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #ST_FAIL_GOTO
	sta stFailureCode
	lda #gotoNameEnd-gotoName
	ldx #<gotoName
	ldy #>gotoName
	jsr st_expect_failure
	bcc .failed

	lda #ST_FAIL_CONTINUE
	sta stFailureCode
	lda #continueNameEnd-continueName
	ldx #<continueName
	ldy #>continueName
	jsr st_expect_failure
	bcc .failed

	lda #ST_FAIL_FOR
	sta stFailureCode
	lda #forNameEnd-forName
	ldx #<forName
	ldy #>forName
	jsr st_expect_failure
	bcc .failed

	lda #ST_FAIL_SWITCH
	sta stFailureCode
	lda #switchNameEnd-switchName
	ldx #<switchName
	ldy #>switchName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_SCANNER_ERROR
	sta stExpectedParser
	lda #LEX_UNEXPECTED_CHARACTER
	sta stExpectedScanner
	lda #ST_FAIL_LABEL
	sta stFailureCode
	lda #labelNameEnd-labelName
	ldx #<labelName
	ldy #>labelName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_BAD_RETURN
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	lda #ST_FAIL_RETURN
	sta stFailureCode
	lda #bareReturnNameEnd-bareReturnName
	ldx #<bareReturnName
	ldy #>bareReturnName
	jsr st_expect_failure
	bcc .failed

	lda #PARSE_BAD_STATEMENT
	sta stExpectedParser
	lda #ST_FAIL_BRACES
	sta stFailureCode
	lda #noBracesNameEnd-noBracesName
	ldx #<noBracesName
	ldy #>noBracesName
	jsr st_expect_failure
	bcc .failed

	sec
	rts
.failed:
	lda stFailureCode
	clc
	rts

;;; A=filename length, X/Y=filename address. Success here means the fixture
;;; failed exactly at the expected compiler layer.
st_expect_failure:
	jsr st_set_source
	jsr open_source
	bcc .openFail
	lda #$00
	sta emitOutputEnabled
	jsr parse_translation_unit
	bcs .unexpectedSuccess
	lda parserError
	cmp stExpectedParser
	bne .wrongFailure
	lda stExpectedScanner
	beq .matched
	lda scannerError
	cmp stExpectedScanner
	bne .wrongFailure
.matched:
	jsr close_source
	sec
	rts
.unexpectedSuccess:
.wrongFailure:
	jsr close_source
	clc
	rts
.openFail:
	lda #ST_FAIL_OPEN
	sta stFailureCode
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Compile real fixtures to ordinary ass source on device 9
;;; ---------------------------------------------------------------------------

;;; A=source filename length, X/Y=source filename address.
st_compile_fixture:
	jsr st_set_source
	jsr open_source
	bcc .openFail
	jsr st_open_output
	bcc .outputFail
	jsr st_emit_header
	bcc .outputFail
	jsr parse_translation_unit
	bcc .compileFail
	jsr st_close_output
	sec
	rts
.openFail:
	lda #ST_FAIL_OPEN
	clc
	rts
.compileFail:
	;;; Keep the same layered one-byte diagnostic convention as the expression
	;;; native compile test.
	lda parserError
	cmp #PARSE_SCANNER_ERROR
	beq .scannerDiagnostic
	cmp #PARSE_EXPRESSION_ERROR
	bne .parserDiagnostic
	lda expressionError
	ora #$80
	jmp .closeDiagnostic
.scannerDiagnostic:
	lda scannerError
	ora #$20
	jmp .closeDiagnostic
.parserDiagnostic:
	ora #$40
.closeDiagnostic:
	sta stCompileDiagnostic
	jsr st_close_output
	lda stCompileDiagnostic
	clc
	rts
.outputFail:
	jsr close_source
	jsr st_close_output
	lda #ST_FAIL_OUTPUT
	clc
	rts

st_set_source:
	sta sourceNameLength
	stx sourceName
	sty sourceName+1
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	rts

;;; A=output filename length, X/Y=output filename address.
st_set_output_name:
	sta stOutputNameLength
	stx stOutputName
	sty stOutputName+1
	rts

st_open_output:
	lda stOutputNameLength
	ldx stOutputName
	ldy stOutputName+1
	jsr SETNAM
	lda #ST_OUTPUT_LFN
	ldx #ST_OUTPUT_DEVICE
	ldy #ST_OUTPUT_LFN
	jsr SETLFS
	jsr OPEN
	bcs .failed
	lda #$01
	sta stOutputOpen
	sta emitOutputEnabled
	sec
	rts
.failed:
	clc
	rts

st_close_output:
	lda #$00
	sta emitOutputEnabled
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda stOutputOpen
	beq .done
	lda #ST_OUTPUT_LFN
	jsr CLOSE
	lda #$00
	sta stOutputOpen
.done:
	rts

st_emit_header:
	lda #stHeaderEnd-stHeader
	ldx #<stHeader
	ldy #>stHeader
	jmp emit_text

;;; ---------------------------------------------------------------------------
;;; Declaration emission hooks used by the generated-program fixtures
;;; ---------------------------------------------------------------------------

;;; A=EMIT_STORAGE_*, X=persistent symbol index.
emit_persistent_symbol:
	sta stStorageKind
	stx stSavedSymbol
	cmp #EMIT_STORAGE_BSS
	beq .bss
	cmp #EMIT_STORAGE_DATA
	beq .data
	;;; EMIT_STORAGE_NONE is a function definition. Its persistent source name
	;;; already exists even though visibility is committed only after the body.
	ldx stSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.bss:
	ldx stSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	jmp st_emit_bss_assignment
.data:
	ldx stSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; X=current-function symbol index; allocOffset is the slot just allocated.
emit_current_symbol:
	stx stSavedSymbol
	jsr emit_current_name
	bcc .failed
	jmp st_emit_bss_assignment
.failed:
	clc
	rts

;;; Each initialized-data byte gets an ordinary one-byte directive. The statement
;;; fixtures currently use BSS globals, but keeping the hook complete means this
;;; driver still exercises the real declaration contract.
emit_static_byte:
	sta stStaticByte
	lda #stBytePrefixEnd-stBytePrefix
	ldx #<stBytePrefix
	ldy #>stBytePrefix
	jsr emit_text
	bcc .failed
	lda stStaticByte
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_bss_boundaries:
	lda #stBssEndPrefixEnd-stBssEndPrefix
	ldx #<stBssEndPrefix
	ldy #>stBssEndPrefix
	jsr emit_text
	bcc .failed
	lda bssOffset
	sta emitWord
	lda bssOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

st_emit_bss_assignment:
	lda #stBssAssignEnd-stBssAssign
	ldx #<stBssAssign
	ldy #>stBssAssign
	jsr emit_text
	bcc .failed
	lda allocOffset
	sta emitWord
	lda allocOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed output text and fixture names
;;; ---------------------------------------------------------------------------

stHeader:
	byte '*',' ','=',' ','$','0','8','0','0',$0a
	byte 'N','C','_','T','M','P',' ','=',' ','$','f','c',$0a
	byte 'N','C','_','P','T','R',' ','=',' ','$','f','e',$0a
	byte 'N','C','_','B','S','S',' ','=',' ','$','3','8','0','0',$0a
	byte $09,'j','m','p',' ','_','_','c','_','m','a','i','n',$0a
stHeaderEnd:
stBytePrefix:	byte $09,'b','y','t','e',' ','$'
stBytePrefixEnd:
stBssAssign:	byte ' ','=',' ','N','C','_','B','S','S','+','$'
stBssAssignEnd:
stBssEndPrefix:	byte '_','_','n','c','_','b','s','s','_','e','n','d',' ','=',' ','N','C','_','B','S','S','+','$'
stBssEndPrefixEnd:

undeclaredName:	byte 'U','N','D','E','C','L','A','R','E','D','.','C'
undeclaredNameEnd:
breakName:	byte 'B','R','E','A','K','O','U','T','.','C'
breakNameEnd:
depthName:	byte 'D','E','P','T','H','B','A','D','.','C'
depthNameEnd:
lateName:	byte 'L','A','T','E','B','L','O','C','K','.','C'
lateNameEnd:
gotoName:	byte 'G','O','T','O','.','C'
gotoNameEnd:
continueName:	byte 'C','O','N','T','I','N','U','E','.','C'
continueNameEnd:
forName:	byte 'F','O','R','.','C'
forNameEnd:
switchName:	byte 'S','W','I','T','C','H','.','C'
switchNameEnd:
labelName:	byte 'L','A','B','E','L','.','C'
labelNameEnd:
bareReturnName:	byte 'B','A','R','E','-','R','E','T','U','R','N','.','C'
bareReturnNameEnd:
noBracesName:	byte 'N','O','-','B','R','A','C','E','S','.','C'
noBracesNameEnd:
returnName:	byte 'R','E','T','U','R','N','8','.','C'
returnNameEnd:
statementName:	byte 'S','T','A','T','E','M','E','N','T','S','.','C'
statementNameEnd:
returnOutputName:	byte 'R','E','T','8','O','U','T','.','A','S','M',',','S',',','W'
returnOutputNameEnd:
statementOutputName:	byte 'S','T','M','T','O','U','T','.','A','S','M',',','S',',','W'
statementOutputNameEnd:

stExpectedParser:	byte 0
stExpectedScanner:	byte 0
stFailureCode:		byte 0
stCompileDiagnostic:	byte 0
stOutputName:		word 0
stOutputNameLength:	byte 0
stOutputOpen:		byte 0
stStorageKind:		byte 0
stSavedSymbol:		byte 0
stStaticByte:		byte 0

	include "declarations.asm"
