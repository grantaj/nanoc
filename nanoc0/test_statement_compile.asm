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
ST_FAIL_CALL       = $0c
ST_FAIL_OPEN       = $0d
ST_FAIL_OUTPUT     = $0e
ST_FAIL_PTR_INT    = $0f
ST_FAIL_INT_PTR    = $10
ST_FAIL_INDEX_PTR  = $11

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

;;; Each language-boundary check is deliberately small. This keeps the test
;;; itself free of long relative branches while making the expected diagnostic
;;; layer visible beside the source case it describes.
st_test_failures:
	jsr st_test_undeclared
	bcs .break
	rts
.break:
	jsr st_test_break_outside
	bcs .depth
	rts
.depth:
	jsr st_test_depth
	bcs .late
	rts
.late:
	jsr st_test_late_local
	bcs .goto
	rts
.goto:
	jsr st_test_goto
	bcs .continue
	rts
.continue:
	jsr st_test_continue
	bcs .for
	rts
.for:
	jsr st_test_for
	bcs .switch
	rts
.switch:
	jsr st_test_switch
	bcs .label
	rts
.label:
	jsr st_test_label
	bcs .return
	rts
.return:
	jsr st_test_bare_return
	bcs .braces
	rts
.braces:
	jsr st_test_braces
	bcs .call
	rts
.call:
	jsr st_test_call_hook
	bcs .pointerFromInt
	rts
.pointerFromInt:
	jsr st_test_pointer_from_int
	bcs .intFromPointer
	rts
.intFromPointer:
	jsr st_test_int_from_pointer
	bcs .indexedPointer
	rts
.indexedPointer:
	jsr st_test_indexed_pointer_value
	rts

st_test_undeclared:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #undeclaredNameEnd-undeclaredName
	ldx #<undeclaredName
	ldy #>undeclaredName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_UNDECLARED
	clc
	rts
.ok:
	sec
	rts

st_test_break_outside:
	lda #PARSE_BREAK_OUTSIDE_LOOP
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #breakNameEnd-breakName
	ldx #<breakName
	ldy #>breakName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_BREAK
	clc
	rts
.ok:
	sec
	rts

st_test_depth:
	lda #PARSE_CONTROL_OVERFLOW
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #depthNameEnd-depthName
	ldx #<depthName
	ldy #>depthName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_DEPTH
	clc
	rts
.ok:
	sec
	rts

st_test_late_local:
	lda #PARSE_LATE_LOCAL
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #lateNameEnd-lateName
	ldx #<lateName
	ldy #>lateName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_LATE
	clc
	rts
.ok:
	sec
	rts

st_test_goto:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #gotoNameEnd-gotoName
	ldx #<gotoName
	ldy #>gotoName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_GOTO
	clc
	rts
.ok:
	sec
	rts

st_test_continue:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #continueNameEnd-continueName
	ldx #<continueName
	ldy #>continueName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_CONTINUE
	clc
	rts
.ok:
	sec
	rts

st_test_for:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #forNameEnd-forName
	ldx #<forName
	ldy #>forName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_FOR
	clc
	rts
.ok:
	sec
	rts

st_test_switch:
	lda #PARSE_UNDECLARED
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #switchNameEnd-switchName
	ldx #<switchName
	ldy #>switchName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_SWITCH
	clc
	rts
.ok:
	sec
	rts

st_test_label:
	lda #PARSE_SCANNER_ERROR
	sta stExpectedParser
	lda #LEX_UNEXPECTED_CHARACTER
	sta stExpectedScanner
	lda #$00
	sta stExpectedExpression
	lda #labelNameEnd-labelName
	ldx #<labelName
	ldy #>labelName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_LABEL
	clc
	rts
.ok:
	sec
	rts

st_test_bare_return:
	lda #PARSE_BAD_RETURN
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #bareReturnNameEnd-bareReturnName
	ldx #<bareReturnName
	ldy #>bareReturnName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_RETURN
	clc
	rts
.ok:
	sec
	rts

st_test_braces:
	lda #PARSE_BAD_STATEMENT
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #noBracesNameEnd-noBracesName
	ldx #<noBracesName
	ldy #>noBracesName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_BRACES
	clc
	rts
.ok:
	sec
	rts

;;; A known runtime call must reach the one #55 call-primary seam. #56 does not
;;; consume any call syntax of its own; #57 will replace EXPR_CALL_UNAVAILABLE.
st_test_call_hook:
	lda #PARSE_EXPRESSION_ERROR
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	lda #EXPR_CALL_UNAVAILABLE
	sta stExpectedExpression
	lda #callNameEnd-callName
	ldx #<callName
	ldy #>callName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_CALL
	clc
	rts
.ok:
	sec
	rts

;;; Pointer/integer assignment is deliberately not an implicit cast in Phase 1.
st_test_pointer_from_int:
	lda #PARSE_BAD_ASSIGNMENT
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #pointerFromIntNameEnd-pointerFromIntName
	ldx #<pointerFromIntName
	ldy #>pointerFromIntName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_PTR_INT
	clc
	rts
.ok:
	sec
	rts

st_test_int_from_pointer:
	lda #PARSE_BAD_ASSIGNMENT
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #intFromPointerNameEnd-intFromPointerName
	ldx #<intFromPointerName
	ldy #>intFromPointerName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_INT_PTR
	clc
	rts
.ok:
	sec
	rts

st_test_indexed_pointer_value:
	lda #PARSE_BAD_ASSIGNMENT
	sta stExpectedParser
	lda #$00
	sta stExpectedScanner
	sta stExpectedExpression
	lda #indexedPointerNameEnd-indexedPointerName
	ldx #<indexedPointerName
	ldy #>indexedPointerName
	jsr st_expect_failure
	bcs .ok
	lda #ST_FAIL_INDEX_PTR
	clc
	rts
.ok:
	sec
	rts

;;; A=filename length, X/Y=filename address. Success means the complete source
;;; fixture failed at exactly the expected compiler layer.
st_expect_failure:
	jsr st_set_source
	jsr open_source
	bcc .openFail
	lda #$00
	sta emitOutputEnabled
	jsr parse_translation_unit
	bcs .wrong
	lda parserError
	cmp stExpectedParser
	bne .wrong
	lda stExpectedScanner
	beq .expression
	lda scannerError
	cmp stExpectedScanner
	bne .wrong
.expression:
	lda stExpectedExpression
	beq .matched
	lda expressionError
	cmp stExpectedExpression
	bne .wrong
.matched:
	jsr close_source
	sec
	rts
.wrong:
	jsr close_source
	clc
	rts
.openFail:
	lda #ST_FAIL_OPEN
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
	;;; Preserve scanner/parser/expression ownership in the one-byte native
	;;; diagnostic just like the expression acceptance test.
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
	jsr close_source
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
;;; Generated-program output
;;; ---------------------------------------------------------------------------
;;;
;;; The acceptance fixtures use the production declaration/runtime output hooks.
;;; Keeping that spelling in program_output.asm means this test cannot quietly
;;; drift away from the source emitted by nanoc0 itself. Only the tiny test header
;;; below differs: it places BSS at $3800 and jumps straight to main.

;;; ---------------------------------------------------------------------------
;;; Fixed output text and fixture names
;;; ---------------------------------------------------------------------------

stHeader:
	byte '*',' ','=',' ','$','0','8','0','0',$0a
	byte 'N','C','_','T','M','P',' ','=',' ','$','f','c',$0a
	byte 'N','C','_','P','T','R',' ','=',' ','$','f','e',$0a
	byte 'N','C','_','B','S','S',' ','=',' ','$','3','8','0','0',$0a
	byte $09,'c','l','d',$0a
	byte $09,'j','m','p',' ','_','_','c','_','m','a','i','n',$0a
stHeaderEnd:

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
callName:	byte 'C','A','L','L','.','C'
callNameEnd:
pointerFromIntName:	byte 'P','O','I','N','T','E','R','-','F','R','O','M','-','I','N','T','.','C'
pointerFromIntNameEnd:
intFromPointerName:	byte 'I','N','T','-','F','R','O','M','-','P','O','I','N','T','E','R','.','C'
intFromPointerNameEnd:
indexedPointerName:	byte 'I','N','D','E','X','E','D','-','P','O','I','N','T','E','R','-','V','A','L','U','E','.','C'
indexedPointerNameEnd:
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
stExpectedExpression:	byte 0
stCompileDiagnostic:	byte 0
stOutputName:		word 0
stOutputNameLength:	byte 0
stOutputOpen:		byte 0

	include "declarations.asm"
	include "program_output.asm"
	include "runtime_codegen.asm"
