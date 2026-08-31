;;; test_statement_skip.asm
;;;
;;; Declaration-test-only function-body skipper.
;;;
;;; #54's declaration and bootstrap capacity tests predate executable statement
;;; compilation and deliberately contain calls that #57 has not implemented yet.
;;; Their Makefile rules define NANOC0_DECLARATION_BODY_SKIP, causing
;;; declarations.asm to include this tiny old boundary walker instead of the
;;; production statements.asm. No production nanoc0 image contains this code.
;;;
;;; Remove this shim when #57 lets those tests traverse ass.c through the normal
;;; statement/call path.

parse_function_statements:
	lda #$00
	sta testBodyBraceDepth
.loop:
	lda currentTokenKind
	cmp #TOKEN_EOF
	beq .unterminated
	jsr is_type_token
	bcs .lateLocal
	lda currentTokenKind
	cmp #TOKEN_IDENTIFIER
	bne .notIdentifier
	jsr lookup_symbol
	bcs .advance
	lda #PARSE_UNDECLARED
	jmp parser_fail
.notIdentifier:
	lda currentTokenKind
	cmp #'{' 
	beq .openBrace
	cmp #'}'
	beq .closeBrace
.advance:
	jsr parser_next
	bcc .failed
	jmp .loop
.openBrace:
	inc testBodyBraceDepth
	beq .unterminated
	jmp .advance
.closeBrace:
	lda testBodyBraceDepth
	beq .functionDone
	dec testBodyBraceDepth
	jmp .advance
.functionDone:
	jmp parser_next
.lateLocal:
	lda #PARSE_LATE_LOCAL
	jmp parser_fail
.unterminated:
	lda #PARSE_UNTERMINATED_FUNCTION
	jmp parser_fail
.failed:
	clc
	rts

testBodyBraceDepth:	byte 0
