	include "../test.inc"

CALL_FAIL_COUNT = $01
CALL_FAIL_TYPE  = $02
CALL_FAIL_LATER = $03
CALL_FAIL_DEPTH = $04
CALL_FAIL_ARGS  = $05
CALL_FAIL_OPEN  = $06

	* = $4000

main:
	lda #EXPR_CALL_ARGUMENT_COUNT
	ldx #<countName
	ldy #>countName
	jsr call_expect_expression_failure
	bcs .type
	lda #CALL_FAIL_COUNT
	jmp call_finish
.type:
	lda #EXPR_CALL_ARGUMENT_TYPE
	ldx #<typeName
	ldy #>typeName
	jsr call_expect_expression_failure
	bcs .later
	lda #CALL_FAIL_TYPE
	jmp call_finish
.later:
	lda #EXPR_UNDECLARED
	ldx #<laterName
	ldy #>laterName
	jsr call_expect_expression_failure
	bcs .depth
	lda #CALL_FAIL_LATER
	jmp call_finish
.depth:
	lda #EXPR_CALL_DEPTH_OVERFLOW
	ldx #<depthName
	ldy #>depthName
	jsr call_expect_expression_failure
	bcs .args
	lda #CALL_FAIL_DEPTH
	jmp call_finish
.args:
	lda #EXPR_CALL_ARGUMENT_OVERFLOW
	ldx #<argsName
	ldy #>argsName
	jsr call_expect_expression_failure
	bcs .pass
	lda #CALL_FAIL_ARGS
	jmp call_finish
.pass:
	lda #TEST_PASS
call_finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; A=expected expression diagnostic, X/Y=eight-byte fixture-name address.
call_expect_expression_failure:
	sta callExpectedExpression
	stx sourceName
	sty sourceName+1
	lda #$08
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	jsr open_source
	bcc .openFailed
	lda #$00
	sta emitOutputEnabled
	jsr parse_translation_unit
	bcs .wrong
	lda parserError
	cmp #PARSE_EXPRESSION_ERROR
	bne .wrong
	lda expressionError
	cmp callExpectedExpression
	bne .wrong
	jsr close_source
	sec
	rts
.wrong:
	jsr close_source
	clc
	rts
.openFailed:
	clc
	rts

;;; These declaration hooks deliberately emit nothing. The test is about parser
;;; bounds/diagnostics; expression text is discarded by emitOutputEnabled=0.
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

countName:	byte 'C','N','T','B','A','D','.','C'
typeName:	byte 'T','Y','P','B','A','D','.','C'
laterName:	byte 'L','A','T','B','A','D','.','C'
depthName:	byte 'D','E','P','B','A','D','.','C'
argsName:	byte 'A','R','G','B','A','D','.','C'

callExpectedExpression:	byte 0

	include "declarations.asm"
