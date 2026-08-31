;;; test_declaration_body_skip.asm
;;;
;;; Test-only function-body walker for the declaration/capacity fixtures that
;;; predate #57 and deliberately contain calls. It lets those tests keep measuring
;;; declaration state without teaching production declarations a second statement
;;; parser. Remove this shim once the call issue lets those fixtures traverse their
;;; bodies normally.
;;;
;;; This file is assembled only when NANOC0_DECLARATION_BODY_SKIP is defined.
;;; Production nanoc0 includes statements.asm instead.

parse_function_statements:
	lda #$00
	sta bodyBraceDepth
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
	inc bodyBraceDepth
	beq .unterminated
	jmp .advance
.closeBrace:
	lda bodyBraceDepth
	beq .functionDone
	dec bodyBraceDepth
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

bodyBraceDepth:	byte 0
