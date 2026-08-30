	include "../test.inc"

FAIL_OPEN            = $01
FAIL_KEYWORDS        = $02
FAIL_IDENTIFIERS     = $03
FAIL_DECIMAL         = $04
FAIL_HEX             = $05
FAIL_LITERALS        = $06
FAIL_PUNCTUATION     = $07
FAIL_COMMENTS_LINES  = $08
FAIL_MIXED_LINES     = $09
FAIL_DEC_OVERFLOW    = $0a
FAIL_HEX_OVERFLOW    = $0b
FAIL_BAD_CHAR        = $0c
FAIL_UNTERM_CHAR     = $0d
FAIL_UNTERM_STRING   = $0e
FAIL_UNTERM_COMMENT  = $0f
FAIL_LONG_IDENTIFIER = $10
FAIL_LONG_STRING     = $11
FAIL_BAD_HEX         = $12
FAIL_UNEXPECTED      = $13
FAIL_SLASH_COMMENT   = $14

;;; The scanner plus its focused native tests are larger than the older tiny
;;; unit tests, so use the ordinary RAM window at $8000-$9fff rather than crowd
;;; the $c000-$cfff page below C64 I/O space.
	* = $8000

main:
	jsr test_valid_tokens
	bcs .lines
	jmp finish
.lines:
	jsr test_mixed_line_endings
	bcs .errors
	jmp finish
.errors:
	jsr test_errors
	bcs .pass
	jmp finish
.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; test_valid_tokens
;;; One real streamed file exercises every valid lexical form.  The assertions
;;; below deliberately inspect scanner state; the host only observes TEST_RESULT.
test_valid_tokens:
	lda #tokensNameEnd-tokensName
	ldx #<tokensName
	ldy #>tokensName
	jsr open_fixture
	bcs .keywords
	lda #FAIL_OPEN
	clc
	rts

.keywords:
	lda #TOKEN_KW_CHAR
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_INT
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_UNSIGNED
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_IF
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_ELSE
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_WHILE
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_BREAK
	jsr expect_kind
	bcc .keywordFail
	lda #TOKEN_KW_RETURN
	jsr expect_kind
	bcs .identifiers
.keywordFail:
	lda #FAIL_KEYWORDS
	clc
	rts

.identifiers:
	;; Near misses remain identifiers and preserve their exact source bytes.
	lda #TOKEN_KW_IF
	jsr expect_kind
	bcc .identifierFail
	lda #TOKEN_IDENTIFIER
	jsr expect_kind
	bcc .identifierFail
	lda currentTokenLength
	cmp #$04
	bne .identifierFail
	lda currentTokenText
	cmp #'i'
	bne .identifierFail
	lda currentTokenText+1
	cmp #'f'
	bne .identifierFail
	lda currentTokenText+2
	cmp #'f'
	bne .identifierFail
	lda currentTokenText+3
	cmp #'y'
	bne .identifierFail

	lda #TOKEN_IDENTIFIER		; IF: case-sensitive, not keyword
	jsr expect_kind
	bcc .identifierFail
	lda currentTokenLength
	cmp #$02
	bne .identifierFail
	lda currentTokenText
	cmp #'I'
	bne .identifierFail
	lda currentTokenText+1
	cmp #'F'
	bne .identifierFail

	lda #TOKEN_IDENTIFIER		; Char
	jsr expect_kind
	bcc .identifierFail
	lda #TOKEN_IDENTIFIER		; _name
	jsr expect_kind
	bcc .identifierFail
	lda currentTokenText
	cmp #'_'
	bne .identifierFail
	lda #TOKEN_IDENTIFIER		; a1
	jsr expect_kind
	bcc .identifierFail
	lda currentTokenText+1
	cmp #'1'
	bne .identifierFail
	lda #TOKEN_IDENTIFIER		; A
	jsr expect_kind
	bcc .identifierFail
	lda #TOKEN_IDENTIFIER		; a
	jsr expect_kind
	bcs .decimal
.identifierFail:
	lda #FAIL_IDENTIFIERS
	clc
	rts

.decimal:
	lda #TOKEN_TYPE_INT
	ldx #$00
	ldy #$00
	jsr expect_number
	bcc .decimalFail
	lda #TOKEN_TYPE_INT
	ldx #$ff
	ldy #$7f
	jsr expect_number
	bcc .decimalFail
	lda #TOKEN_TYPE_UNSIGNED
	ldx #$00
	ldy #$80
	jsr expect_number
	bcc .decimalFail
	lda #TOKEN_TYPE_UNSIGNED
	ldx #$ff
	ldy #$ff
	jsr expect_number
	bcs .hex
.decimalFail:
	lda #FAIL_DECIMAL
	clc
	rts

.hex:
	lda #TOKEN_TYPE_INT
	ldx #$00
	ldy #$00
	jsr expect_number
	bcc .hexFail
	lda #TOKEN_TYPE_INT
	ldx #$ff
	ldy #$7f
	jsr expect_number
	bcc .hexFail
	lda #TOKEN_TYPE_UNSIGNED
	ldx #$00
	ldy #$80
	jsr expect_number
	bcc .hexFail
	lda #TOKEN_TYPE_UNSIGNED
	ldx #$cd
	ldy #$ab
	jsr expect_number
	bcc .hexFail
	lda #TOKEN_TYPE_UNSIGNED
	ldx #$ff
	ldy #$ff
	jsr expect_number
	bcs .literals
.hexFail:
	lda #FAIL_HEX
	clc
	rts

.literals:
	lda #'A'
	jsr expect_character
	bcc .literalFail
	lda #' '
	jsr expect_character
	bcc .literalFail
	lda #';'
	jsr expect_character
	bcc .literalFail

	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_STRING
	bne .literalFail
	lda currentTokenLength
	cmp #$03
	bne .literalFail
	lda currentTokenText
	cmp #'a'
	bne .literalFail
	lda currentTokenText+1
	cmp #'b'
	bne .literalFail
	lda currentTokenText+2
	cmp #'c'
	bne .literalFail

	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_STRING
	bne .literalFail
	lda currentTokenLength
	beq .punctuation
.literalFail:
	lda #FAIL_LITERALS
	clc
	rts

.punctuation:
	ldx #$00
.punctuationLoop:
	stx testIndex
	lda expectedPunctuation,x
	jsr expect_kind
	bcc .punctuationFail
	ldx testIndex
	inx
	cpx #expectedPunctuationEnd-expectedPunctuation
	bne .punctuationLoop
	jmp .comments
.punctuationFail:
	lda #FAIL_PUNCTUATION
	clc
	rts

.comments:
	;; No whitespace is needed around a discarded block comment.  Its newline
	;; still advances the line counter before the following token.
	lda #TOKEN_IDENTIFIER		; foo, line 7
	jsr expect_kind
	bcc .commentsFail
	lda currentTokenLine
	cmp #$07
	bne .commentsFail
	lda #TOKEN_IDENTIFIER		; bar, line 8 after comment newline
	jsr expect_kind
	bcc .commentsFail
	lda currentTokenLine
	cmp #$08
	bne .commentsFail
	lda #TOKEN_IDENTIFIER		; baz, line 9
	jsr expect_kind
	bcc .commentsFail
	lda #'+'				; token separated by physical lines
	jsr expect_kind
	bcc .commentsFail
	lda #TOKEN_IDENTIFIER		; qux, line 11
	jsr expect_kind
	bcc .commentsFail
	lda currentTokenLine
	cmp #$0b
	bne .commentsFail
	lda #TOKEN_EOF
	jsr expect_kind
	bcc .commentsFail
	sec
	rts
.commentsFail:
	lda #FAIL_COMMENTS_LINES
	clc
	rts

;;; A CRLF, a bare LF and a bare CR must each advance exactly one source line.
test_mixed_line_endings:
	lda #linesNameEnd-linesName
	ldx #<linesName
	ldy #>linesName
	jsr open_fixture
	bcs .line1
	lda #FAIL_OPEN
	clc
	rts
.line1:
	lda #TOKEN_KW_INT
	ldx #$01
	jsr expect_kind_line
	bcc .fail
	lda #TOKEN_KW_CHAR
	ldx #$02
	jsr expect_kind_line
	bcc .fail
	lda #TOKEN_KW_UNSIGNED
	ldx #$03
	jsr expect_kind_line
	bcc .fail
	lda #TOKEN_KW_RETURN
	ldx #$04
	jsr expect_kind_line
	bcc .fail
	sec
	rts
.fail:
	lda #FAIL_MIXED_LINES
	clc
	rts

;;; Each malformed fixture stops at one deliberate lexical error.  Keeping the
;;; expectations here makes it obvious which native scanner status is required.
test_errors:
	lda #odecNameEnd-odecName
	ldx #<odecName
	ldy #>odecName
	jsr open_fixture
	bcs .opened1
	lda #FAIL_OPEN
	clc
	rts
.opened1:
	lda #LEX_INTEGER_OVERFLOW
	jsr expect_error
	bcs .hexOverflow
	lda #FAIL_DEC_OVERFLOW
	clc
	rts
.hexOverflow:
	lda #ohexNameEnd-ohexName
	ldx #<ohexName
	ldy #>ohexName
	jsr open_fixture
	bcs .opened2
	lda #FAIL_OPEN
	clc
	rts
.opened2:
	lda #LEX_INTEGER_OVERFLOW
	jsr expect_error
	bcs .badChar
	lda #FAIL_HEX_OVERFLOW
	clc
	rts
.badChar:
	lda #badCharNameEnd-badCharName
	ldx #<badCharName
	ldy #>badCharName
	jsr open_fixture
	bcs .opened3
	lda #FAIL_OPEN
	clc
	rts
.opened3:
	lda #LEX_BAD_CHAR_LENGTH
	jsr expect_error
	bcs .untermChar
	lda #FAIL_BAD_CHAR
	clc
	rts
.untermChar:
	lda #ucharNameEnd-ucharName
	ldx #<ucharName
	ldy #>ucharName
	jsr open_fixture
	bcs .opened4
	lda #FAIL_OPEN
	clc
	rts
.opened4:
	lda #LEX_UNTERMINATED_CHAR
	jsr expect_error
	bcs .untermString
	lda #FAIL_UNTERM_CHAR
	clc
	rts
.untermString:
	lda #ustrNameEnd-ustrName
	ldx #<ustrName
	ldy #>ustrName
	jsr open_fixture
	bcs .opened5
	lda #FAIL_OPEN
	clc
	rts
.opened5:
	lda #LEX_UNTERMINATED_STRING
	jsr expect_error
	bcs .untermComment
	lda #FAIL_UNTERM_STRING
	clc
	rts
.untermComment:
	lda #ucomNameEnd-ucomName
	ldx #<ucomName
	ldy #>ucomName
	jsr open_fixture
	bcs .opened6
	lda #FAIL_OPEN
	clc
	rts
.opened6:
	lda #LEX_UNTERMINATED_COMMENT
	jsr expect_error
	bcs .longIdentifier
	lda #FAIL_UNTERM_COMMENT
	clc
	rts
.longIdentifier:
	lda #longIdNameEnd-longIdName
	ldx #<longIdName
	ldy #>longIdName
	jsr open_fixture
	bcs .opened7
	lda #FAIL_OPEN
	clc
	rts
.opened7:
	lda #LEX_TEXT_TOO_LONG
	jsr expect_error
	bcs .longString
	lda #FAIL_LONG_IDENTIFIER
	clc
	rts
.longString:
	lda #longStringNameEnd-longStringName
	ldx #<longStringName
	ldy #>longStringName
	jsr open_fixture
	bcs .opened8
	lda #FAIL_OPEN
	clc
	rts
.opened8:
	lda #LEX_TEXT_TOO_LONG
	jsr expect_error
	bcs .badHex
	lda #FAIL_LONG_STRING
	clc
	rts
.badHex:
	lda #badHexNameEnd-badHexName
	ldx #<badHexName
	ldy #>badHexName
	jsr open_fixture
	bcs .opened9
	lda #FAIL_OPEN
	clc
	rts
.opened9:
	lda #LEX_BAD_HEX
	jsr expect_error
	bcs .unexpected
	lda #FAIL_BAD_HEX
	clc
	rts
.unexpected:
	lda #badNameEnd-badName
	ldx #<badName
	ldy #>badName
	jsr open_fixture
	bcs .opened10
	lda #FAIL_OPEN
	clc
	rts
.opened10:
	lda #LEX_UNEXPECTED_CHARACTER
	jsr expect_error
	bcc .unexpectedFail
	lda currentTokenLine
	cmp #$03			; two leading physical lines in BAD.C
	bne .unexpectedFail
	jmp .slashComment
.unexpectedFail:
	lda #FAIL_UNEXPECTED
	clc
	rts
.slashComment:
	lda #slashNameEnd-slashName
	ldx #<slashName
	ldy #>slashName
	jsr open_fixture
	bcs .opened11
	lda #FAIL_OPEN
	clc
	rts
.opened11:
	lda #LEX_UNEXPECTED_CHARACTER
	jsr expect_error
	bcs .done
	lda #FAIL_SLASH_COMMENT
	clc
	rts
.done:
	sec
	rts

;;; open_fixture
;;; A=filename length, X/Y=filename address.
open_fixture:
	sta sourceNameLength
	stx sourceName
	sty sourceName+1
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	jsr open_source
	rts

;;; expect_kind
;;; A=expected token kind. Carry set on match.
expect_kind:
	sta expectedKind
	jsr next_token
	lda currentTokenKind
	cmp expectedKind
	beq .yes
	clc
	rts
.yes:
	sec
	rts

;;; expect_kind_line
;;; A=expected kind, X=expected one-byte line number.
expect_kind_line:
	sta expectedKind
	stx expectedLine
	jsr next_token
	lda currentTokenKind
	cmp expectedKind
	bne .no
	lda currentTokenLine
	cmp expectedLine
	bne .no
	lda currentTokenLine+1
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; expect_number
;;; A=expected type, X/Y=expected low/high value.
expect_number:
	sta expectedType
	stx expectedValue
	sty expectedValue+1
	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_INTEGER
	bne .no
	lda currentTokenType
	cmp expectedType
	bne .no
	lda currentTokenValue
	cmp expectedValue
	bne .no
	lda currentTokenValue+1
	cmp expectedValue+1
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; expect_character
;;; A=expected byte value.
expect_character:
	sta expectedValue
	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_CHARACTER
	bne .no
	lda currentTokenType
	cmp #TOKEN_TYPE_INT
	bne .no
	lda currentTokenValue
	cmp expectedValue
	bne .no
	lda currentTokenValue+1
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; expect_error
;;; A=expected scannerError. Carry set when next_token reports exactly it.
expect_error:
	sta expectedError
	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_ERROR
	bne .no
	lda scannerError
	cmp expectedError
	bne .no
	sec
	rts
.no:
	clc
	rts

expectedPunctuation:
	byte '(',')','{','}','[',']',';',','
	byte '=','+','-','*','<','>','&','|'
	byte TOKEN_EQ,TOKEN_NE,TOKEN_LE,TOKEN_GE,TOKEN_SHL,TOKEN_SHR
expectedPunctuationEnd:

tokensName:
	byte 'T','O','K','E','N','S','.','C'
tokensNameEnd:
linesName:
	byte 'L','I','N','E','S','.','C'
linesNameEnd:
odecName:
	byte 'O','D','E','C','.','C'
odecNameEnd:
ohexName:
	byte 'O','H','E','X','.','C'
ohexNameEnd:
badCharName:
	byte 'B','A','D','C','H','A','R','.','C'
badCharNameEnd:
ucharName:
	byte 'U','C','H','A','R','.','C'
ucharNameEnd:
ustrName:
	byte 'U','S','T','R','.','C'
ustrNameEnd:
ucomName:
	byte 'U','C','O','M','.','C'
ucomNameEnd:
longIdName:
	byte 'L','O','N','G','I','D','.','C'
longIdNameEnd:
longStringName:
	byte 'L','O','N','G','S','T','R','.','C'
longStringNameEnd:
badHexName:
	byte 'B','A','D','H','E','X','.','C'
badHexNameEnd:
badName:
	byte 'B','A','D','.','C'
badNameEnd:
slashName:
	byte 'S','L','A','S','H','.','C'
slashNameEnd:

expectedKind:	byte 0
expectedType:	byte 0
expectedLine:	byte 0
expectedError:	byte 0
expectedValue:	word 0
testIndex:	byte 0

	include "scanner.asm"
