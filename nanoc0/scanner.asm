;;; scanner.asm
;;;
;;; Nano C Phase 1 scanner.
;;;
;;; source.asm supplies one normalised source byte at a time.  This file turns
;;; that stream into exactly one reusable current token.  There is no token
;;; array, source copy, allocation, AST or parser state here.
;;;
;;; Character predicates in this file take the byte in A, return their answer in
;;; carry, and preserve A.  That matters because a failed lookahead is pushed
;;; straight back to the source reader.

	include "source.asm"

SOURCE_TAB               = $09
ASCII_SINGLE_QUOTE       = $27
ASCII_DOUBLE_QUOTE       = $22
ASCII_BACKSLASH          = $5c

TOKEN_TEXT_CAPACITY      = 64

TOKEN_EOF                = $80
TOKEN_ERROR              = $81
TOKEN_IDENTIFIER         = $82
TOKEN_INTEGER            = $83
TOKEN_CHARACTER          = $84
TOKEN_STRING             = $85
TOKEN_KW_CHAR            = $86
TOKEN_KW_INT             = $87
TOKEN_KW_UNSIGNED        = $88
TOKEN_KW_IF              = $89
TOKEN_KW_ELSE            = $8a
TOKEN_KW_WHILE           = $8b
TOKEN_KW_BREAK           = $8c
TOKEN_KW_RETURN          = $8d
TOKEN_EQ                 = $8e
TOKEN_NE                 = $8f
TOKEN_LE                 = $90
TOKEN_GE                 = $91
TOKEN_SHL                = $92
TOKEN_SHR                = $93

TOKEN_TYPE_NONE          = 0
TOKEN_TYPE_INT           = 1
TOKEN_TYPE_UNSIGNED      = 2

LEX_OK                   = 0
LEX_UNTERMINATED_COMMENT = 1
LEX_UNTERMINATED_CHAR    = 2
LEX_BAD_CHAR_LENGTH      = 3
LEX_UNTERMINATED_STRING  = 4
LEX_INTEGER_OVERFLOW     = 5
LEX_TEXT_TOO_LONG        = 6
LEX_UNEXPECTED_CHARACTER = 7
LEX_IO_ERROR             = 8
LEX_BAD_HEX              = 9
LEX_UNSUPPORTED_ESCAPE   = 10

;;; next_token
;;; Consume source bytes until one Phase 1 token replaces currentToken*.
;;;
;;; TOKEN_ERROR is terminal for the compiler.  Individual tests may open a new
;;; source and call next_token again, but recovery within malformed input is not
;;; part of the scanner contract.
next_token:
	lda #LEX_OK
	sta scannerError
.again:
	jsr read_source_byte
	bcs .haveByte
	cmp #SOURCE_STATE_EOF
	bne .inputError
	jmp .eof
.inputError:
	jsr begin_current_token
	lda #LEX_IO_ERROR
	jmp set_lex_error

.haveByte:
	cmp #' '
	beq .again
	cmp #SOURCE_TAB
	beq .again
	cmp #SOURCE_LF
	beq .again

.tokenStart:
	sta scanByte
	jsr begin_current_token
	lda scanByte

	;; '/' exists in Phase 1 only as the opening half of a block comment.
	cmp #'/'
	bne .notSlash
	jsr read_source_byte
	bcs .slashSecond
	cmp #SOURCE_STATE_IO_ERROR
	bne .slashUnexpected
	jmp .ioError
.slashUnexpected:
	lda #LEX_UNEXPECTED_CHARACTER	; bare '/' at EOF
	jmp set_lex_error
.slashSecond:
	cmp #'*'
	beq .comment
	jsr push_source_byte
	lda #LEX_UNEXPECTED_CHARACTER
	jmp set_lex_error
.comment:
	jsr skip_block_comment
	bcc .commentError
	jmp .again
.commentError:
	jmp set_lex_error		; A is the comment error reason

.notSlash:
	jsr is_identifier_start
	bcc .notIdentifier
	jmp scan_identifier

.notIdentifier:
	jsr is_decimal_digit
	bcc .notNumber
	jmp scan_number

.notNumber:
	cmp #ASCII_SINGLE_QUOTE
	bne .notCharacter
	jmp scan_character_literal
.notCharacter:
	cmp #ASCII_DOUBLE_QUOTE
	bne .notString
	jmp scan_string_literal
.notString:
	cmp #'='
	bne .notEquals
	jmp scan_equals
.notEquals:
	cmp #'!'
	bne .notBang
	jmp scan_bang
.notBang:
	cmp #'<'
	bne .notLess
	jmp scan_less
.notLess:
	cmp #'>'
	bne .singlePunctuation
	jmp scan_greater

.singlePunctuation:
	cmp #'('
	beq .single
	cmp #')'
	beq .single
	cmp #'{' 
	beq .single
	cmp #'}'
	beq .single
	cmp #'['
	beq .single
	cmp #']'
	beq .single
	cmp #';'
	beq .single
	cmp #','
	beq .single
	cmp #'+'
	beq .single
	cmp #'-'
	beq .single
	cmp #'*'
	beq .single
	cmp #'&'
	beq .single
	cmp #'|'
	beq .single
	lda #LEX_UNEXPECTED_CHARACTER
	jmp set_lex_error
.single:
	sta currentTokenKind
	rts

.ioError:
	lda #LEX_IO_ERROR
	jmp set_lex_error

.eof:
	jsr begin_current_token
	lda #TOKEN_EOF
	sta currentTokenKind
	rts

;;; begin_current_token
;;; Reset the fields whose previous values must not survive.  The text buffer is
;;; deliberately not cleared and is not NUL terminated: only bytes
;;; [0,currentTokenLength) belong to the current token.
begin_current_token:
	lda #TOKEN_TYPE_NONE
	sta currentTokenType
	lda #$00
	sta currentTokenValue
	sta currentTokenValue+1
	sta currentTokenLength
	lda sourceLine
	sta currentTokenLine
	lda sourceLine+1
	sta currentTokenLine+1
	rts

set_lex_error:
	sta scannerError
	lda #TOKEN_ERROR
	sta currentTokenKind
	rts

;;; skip_block_comment
;;; Carry set: closing */ consumed.
;;; Carry clear: A is LEX_UNTERMINATED_COMMENT or LEX_IO_ERROR.
;;; source.asm already accounts for any newline bytes consumed here.
skip_block_comment:
.loop:
	jsr read_source_byte
	bcc .noByte
	cmp #'*'
	bne .loop

.afterStar:
	jsr read_source_byte
	bcc .noByte
	cmp #'/'
	beq .done
	cmp #'*'
	beq .afterStar
	jmp .loop

.noByte:
	cmp #SOURCE_STATE_IO_ERROR
	bne .unterminated
	lda #LEX_IO_ERROR
	clc
	rts
.unterminated:
	lda #LEX_UNTERMINATED_COMMENT
	clc
	rts
.done:
	sec
	rts

;;; scan_identifier
;;; A is the first identifier byte.
scan_identifier:
	jsr append_token_byte
	bcs .more
	lda #LEX_TEXT_TOO_LONG
	jmp set_lex_error
.more:
	jsr read_source_byte
	bcc .endSource
	jsr is_identifier_continue
	bcc .lookahead
	jsr append_token_byte
	bcs .more
	lda #LEX_TEXT_TOO_LONG
	jmp set_lex_error
.lookahead:
	jsr push_source_byte
	jmp classify_identifier
.endSource:
	cmp #SOURCE_STATE_EOF
	beq classify_identifier
	lda #LEX_IO_ERROR
	jmp set_lex_error

;;; classify_identifier
;;; Phase 1 has only eight keywords.  Dispatch by identifier length and compare
;;; those words directly so the language vocabulary is visible in the code.
classify_identifier:
	lda currentTokenLength
	cmp #$02
	bne .not2
	jmp .checkIf
.not2:
	cmp #$03
	bne .not3
	jmp .checkInt
.not3:
	cmp #$04
	bne .not4
	jmp .checkLength4
.not4:
	cmp #$05
	bne .not5
	jmp .checkLength5
.not5:
	cmp #$06
	bne .not6
	jmp .checkReturn
.not6:
	cmp #$08
	bne .not8
	jmp .checkUnsigned
.not8:
	jmp set_identifier

.checkIf:
	lda currentTokenText
	cmp #'i'
	beq .ifSecond
	jmp set_identifier
.ifSecond:
	lda currentTokenText+1
	cmp #'f'
	beq .ifKeyword
	jmp set_identifier
.ifKeyword:
	lda #TOKEN_KW_IF
	sta currentTokenKind
	rts

.checkInt:
	lda currentTokenText
	cmp #'i'
	beq .intSecond
	jmp set_identifier
.intSecond:
	lda currentTokenText+1
	cmp #'n'
	beq .intThird
	jmp set_identifier
.intThird:
	lda currentTokenText+2
	cmp #'t'
	beq .intKeyword
	jmp set_identifier
.intKeyword:
	lda #TOKEN_KW_INT
	sta currentTokenKind
	rts

.checkLength4:
	lda currentTokenText
	cmp #'c'
	beq .checkChar
	cmp #'e'
	beq .checkElse
	jmp set_identifier
.checkChar:
	lda currentTokenText+1
	cmp #'h'
	beq .charThird
	jmp set_identifier
.charThird:
	lda currentTokenText+2
	cmp #'a'
	beq .charFourth
	jmp set_identifier
.charFourth:
	lda currentTokenText+3
	cmp #'r'
	beq .charKeyword
	jmp set_identifier
.charKeyword:
	lda #TOKEN_KW_CHAR
	sta currentTokenKind
	rts
.checkElse:
	lda currentTokenText+1
	cmp #'l'
	beq .elseThird
	jmp set_identifier
.elseThird:
	lda currentTokenText+2
	cmp #'s'
	beq .elseFourth
	jmp set_identifier
.elseFourth:
	lda currentTokenText+3
	cmp #'e'
	beq .elseKeyword
	jmp set_identifier
.elseKeyword:
	lda #TOKEN_KW_ELSE
	sta currentTokenKind
	rts

.checkLength5:
	lda currentTokenText
	cmp #'w'
	beq .checkWhile
	cmp #'b'
	beq .checkBreak
	jmp set_identifier
.checkWhile:
	lda currentTokenText+1
	cmp #'h'
	beq .whileThird
	jmp set_identifier
.whileThird:
	lda currentTokenText+2
	cmp #'i'
	beq .whileFourth
	jmp set_identifier
.whileFourth:
	lda currentTokenText+3
	cmp #'l'
	beq .whileFifth
	jmp set_identifier
.whileFifth:
	lda currentTokenText+4
	cmp #'e'
	beq .whileKeyword
	jmp set_identifier
.whileKeyword:
	lda #TOKEN_KW_WHILE
	sta currentTokenKind
	rts
.checkBreak:
	lda currentTokenText+1
	cmp #'r'
	beq .breakThird
	jmp set_identifier
.breakThird:
	lda currentTokenText+2
	cmp #'e'
	beq .breakFourth
	jmp set_identifier
.breakFourth:
	lda currentTokenText+3
	cmp #'a'
	beq .breakFifth
	jmp set_identifier
.breakFifth:
	lda currentTokenText+4
	cmp #'k'
	beq .breakKeyword
	jmp set_identifier
.breakKeyword:
	lda #TOKEN_KW_BREAK
	sta currentTokenKind
	rts

.checkReturn:
	lda currentTokenText
	cmp #'r'
	beq .returnSecond
	jmp set_identifier
.returnSecond:
	lda currentTokenText+1
	cmp #'e'
	beq .returnThird
	jmp set_identifier
.returnThird:
	lda currentTokenText+2
	cmp #'t'
	beq .returnFourth
	jmp set_identifier
.returnFourth:
	lda currentTokenText+3
	cmp #'u'
	beq .returnFifth
	jmp set_identifier
.returnFifth:
	lda currentTokenText+4
	cmp #'r'
	beq .returnSixth
	jmp set_identifier
.returnSixth:
	lda currentTokenText+5
	cmp #'n'
	beq .returnKeyword
	jmp set_identifier
.returnKeyword:
	lda #TOKEN_KW_RETURN
	sta currentTokenKind
	rts

.checkUnsigned:
	lda currentTokenText
	cmp #'u'
	beq .unsignedSecond
	jmp set_identifier
.unsignedSecond:
	lda currentTokenText+1
	cmp #'n'
	beq .unsignedThird
	jmp set_identifier
.unsignedThird:
	lda currentTokenText+2
	cmp #'s'
	beq .unsignedFourth
	jmp set_identifier
.unsignedFourth:
	lda currentTokenText+3
	cmp #'i'
	beq .unsignedFifth
	jmp set_identifier
.unsignedFifth:
	lda currentTokenText+4
	cmp #'g'
	beq .unsignedSixth
	jmp set_identifier
.unsignedSixth:
	lda currentTokenText+5
	cmp #'n'
	beq .unsignedSeventh
	jmp set_identifier
.unsignedSeventh:
	lda currentTokenText+6
	cmp #'e'
	beq .unsignedEighth
	jmp set_identifier
.unsignedEighth:
	lda currentTokenText+7
	cmp #'d'
	beq .unsignedKeyword
	jmp set_identifier
.unsignedKeyword:
	lda #TOKEN_KW_UNSIGNED
	sta currentTokenKind
	rts

set_identifier:
	lda #TOKEN_IDENTIFIER
	sta currentTokenKind
	rts

;;; append_token_byte
;;; Append A to the shared identifier/string buffer. Carry clear means full.
append_token_byte:
	ldx currentTokenLength
	cpx #TOKEN_TEXT_CAPACITY
	bcs .full
	sta currentTokenText,x
	inc currentTokenLength
	sec
	rts
.full:
	clc
	rts

;;; Character predicates
;;; Input: A is the source byte.
;;; Output: carry says yes/no; A is unchanged.
is_identifier_start:
	cmp #'_'
	beq .yes
	cmp #'A'
	bcc .no
	cmp #'Z'+1
	bcc .yes
	cmp #'a'
	bcc .no
	cmp #'z'+1
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

is_identifier_continue:
	jsr is_identifier_start
	bcs .yes
	jsr is_decimal_digit
	rts
.yes:
	sec
	rts

is_decimal_digit:
	cmp #'0'
	bcc .no
	cmp #'9'+1
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

;;; scan_number
;;; A is the first decimal digit.  Leading zero remains decimal unless followed
;;; immediately by x/X, matching the frozen Phase 1 literal syntax (no octal).
scan_number:
	cmp #'0'
	bne .firstDecimal
	lda #$00
	sta currentTokenValue
	sta currentTokenValue+1
	jsr read_source_byte
	bcc .zeroEndSource
	cmp #'x'
	beq .hexJump
	cmp #'X'
	bne .notHexPrefix
.hexJump:
	jmp .hex
.notHexPrefix:
	jsr is_decimal_digit
	bcc .zeroLookahead
	jmp .decimalDigit
.zeroLookahead:
	jsr push_source_byte
	jmp finish_integer
.zeroEndSource:
	cmp #SOURCE_STATE_EOF
	bne .zeroIo
	jmp finish_integer
.zeroIo:
	lda #LEX_IO_ERROR
	jmp set_lex_error

.firstDecimal:
	pha
	lda #$00
	sta currentTokenValue
	sta currentTokenValue+1
	pla

.decimalDigit:
	jsr accumulate_decimal_digit
	bcs .decimalMore
	lda #LEX_INTEGER_OVERFLOW
	jmp set_lex_error
.decimalMore:
	jsr read_source_byte
	bcc .decimalEndSource
	jsr is_decimal_digit
	bcs .decimalDigit
	jsr push_source_byte
	jmp finish_integer
.decimalEndSource:
	cmp #SOURCE_STATE_EOF
	bne .decimalIo
	jmp finish_integer
.decimalIo:
	lda #LEX_IO_ERROR
	jmp set_lex_error

.hex:
	jsr read_source_byte
	bcc .hexMissingSource
	jsr hex_digit_value
	bcc .hexMissingDigit
.hexDigit:
	jsr accumulate_hex_digit
	bcs .hexMore
	lda #LEX_INTEGER_OVERFLOW
	jmp set_lex_error
.hexMore:
	jsr read_source_byte
	bcc .hexEndSource
	jsr hex_digit_value
	bcs .hexDigit
	jsr push_source_byte
	jmp finish_integer
.hexMissingDigit:
	;; hex_digit_value preserves the non-digit source byte in A on failure.
	jsr push_source_byte
	lda #LEX_BAD_HEX
	jmp set_lex_error
.hexMissingSource:
	cmp #SOURCE_STATE_IO_ERROR
	beq .hexIo
	lda #LEX_BAD_HEX
	jmp set_lex_error
.hexEndSource:
	cmp #SOURCE_STATE_EOF
	bne .hexIo
	jmp finish_integer
.hexIo:
	lda #LEX_IO_ERROR
	jmp set_lex_error

;;; accumulate_decimal_digit
;;; A is ASCII '0'..'9'.  Reject before calculating when value*10+digit would
;;; exceed 65535.  $1999 is 6553, the largest safe pre-multiply value.
accumulate_decimal_digit:
	sec
	sbc #'0'
	sta scanDigit
	lda currentTokenValue+1
	cmp #$19
	bcc .safe
	beq .checkLow
	clc
	rts
.checkLow:
	lda currentTokenValue
	cmp #$99
	bcc .safe
	beq .checkDigit
	clc
	rts
.checkDigit:
	lda scanDigit
	cmp #$06
	bcc .safe
	clc
	rts
.safe:
	lda currentTokenValue
	sta scanTemp
	lda currentTokenValue+1
	sta scanTemp+1

	;; currentTokenValue = old * 2
	asl currentTokenValue
	rol currentTokenValue+1
	;; scanTemp = old * 8
	asl scanTemp
	rol scanTemp+1
	asl scanTemp
	rol scanTemp+1
	asl scanTemp
	rol scanTemp+1
	;; currentTokenValue = old*10 + digit
	clc
	lda currentTokenValue
	adc scanTemp
	sta currentTokenValue
	lda currentTokenValue+1
	adc scanTemp+1
	sta currentTokenValue+1
	clc
	lda currentTokenValue
	adc scanDigit
	sta currentTokenValue
	bcc .done
	inc currentTokenValue+1
.done:
	sec
	rts

;;; hex_digit_value
;;; Input: A is the source byte.
;;; Carry set:   A is the digit value 0..15.
;;; Carry clear: A is the original source byte unchanged.
hex_digit_value:
	cmp #'0'
	bcc .tryUpper
	cmp #'9'+1
	bcs .tryUpper
	sec
	sbc #'0'
	sec
	rts
.tryUpper:
	cmp #'A'
	bcc .tryLower
	cmp #'F'+1
	bcs .tryLower
	sec
	sbc #'A'-10
	sec
	rts
.tryLower:
	cmp #'a'
	bcc .no
	cmp #'f'+1
	bcs .no
	sec
	sbc #'a'-10
	sec
	rts
.no:
	clc
	rts

;;; accumulate_hex_digit
;;; A is 0..15. A fifth significant hex digit cannot fit when the current high
;;; nibble is already nonzero.
accumulate_hex_digit:
	sta scanDigit
	lda currentTokenValue+1
	and #$f0
	bne .overflow
	asl currentTokenValue
	rol currentTokenValue+1
	asl currentTokenValue
	rol currentTokenValue+1
	asl currentTokenValue
	rol currentTokenValue+1
	asl currentTokenValue
	rol currentTokenValue+1
	lda currentTokenValue
	ora scanDigit
	sta currentTokenValue
	sec
	rts
.overflow:
	clc
	rts

finish_integer:
	lda #TOKEN_INTEGER
	sta currentTokenKind
	lda currentTokenValue+1
	bpl .signed
	lda #TOKEN_TYPE_UNSIGNED
	sta currentTokenType
	rts
.signed:
	lda #TOKEN_TYPE_INT
	sta currentTokenType
	rts

scan_character_literal:
	jsr read_source_byte
	bcc .missingFirst
	cmp #SOURCE_LF
	bne .notLine
	lda #LEX_UNTERMINATED_CHAR
	jmp set_lex_error
.notLine:
	cmp #ASCII_BACKSLASH
	bne .notEscape
	lda #LEX_UNSUPPORTED_ESCAPE
	jmp set_lex_error
.notEscape:
	cmp #ASCII_SINGLE_QUOTE
	bne .haveCharacter
	lda #LEX_BAD_CHAR_LENGTH		; empty character literal
	jmp set_lex_error
.haveCharacter:
	sta currentTokenValue
	lda #$00
	sta currentTokenValue+1
	jsr read_source_byte
	bcc .missingClose
	cmp #SOURCE_LF
	bne .checkClose
	lda #LEX_UNTERMINATED_CHAR
	jmp set_lex_error
.checkClose:
	cmp #ASCII_SINGLE_QUOTE
	beq .done
	lda #LEX_BAD_CHAR_LENGTH
	jmp set_lex_error
.done:
	lda #TOKEN_CHARACTER
	sta currentTokenKind
	lda #TOKEN_TYPE_INT
	sta currentTokenType
	rts
.missingFirst:
.missingClose:
	cmp #SOURCE_STATE_IO_ERROR
	beq .io
	lda #LEX_UNTERMINATED_CHAR
	jmp set_lex_error
.io:
	lda #LEX_IO_ERROR
	jmp set_lex_error

scan_string_literal:
.loop:
	jsr read_source_byte
	bcc .missingClose
	cmp #SOURCE_LF
	bne .notLine
	lda #LEX_UNTERMINATED_STRING
	jmp set_lex_error
.notLine:
	cmp #ASCII_BACKSLASH
	bne .notEscape
	lda #LEX_UNSUPPORTED_ESCAPE
	jmp set_lex_error
.notEscape:
	cmp #ASCII_DOUBLE_QUOTE
	beq .done
	jsr append_token_byte
	bcs .loop
	lda #LEX_TEXT_TOO_LONG
	jmp set_lex_error
.done:
	lda #TOKEN_STRING
	sta currentTokenKind
	rts
.missingClose:
	cmp #SOURCE_STATE_IO_ERROR
	beq .io
	lda #LEX_UNTERMINATED_STRING
	jmp set_lex_error
.io:
	lda #LEX_IO_ERROR
	jmp set_lex_error

scan_equals:
	jsr read_source_byte
	bcc .noSecond
	cmp #'='
	beq .double
	jsr push_source_byte
.single:
	lda #'='
	sta currentTokenKind
	rts
.double:
	lda #TOKEN_EQ
	sta currentTokenKind
	rts
.noSecond:
	cmp #SOURCE_STATE_EOF
	beq .single
	lda #LEX_IO_ERROR
	jmp set_lex_error

scan_bang:
	jsr read_source_byte
	bcc .noSecond
	cmp #'='
	beq .double
	jsr push_source_byte
	lda #LEX_UNEXPECTED_CHARACTER
	jmp set_lex_error
.double:
	lda #TOKEN_NE
	sta currentTokenKind
	rts
.noSecond:
	cmp #SOURCE_STATE_IO_ERROR
	beq .io
	lda #LEX_UNEXPECTED_CHARACTER
	jmp set_lex_error
.io:
	lda #LEX_IO_ERROR
	jmp set_lex_error

scan_less:
	jsr read_source_byte
	bcc .noSecond
	cmp #'='
	beq .equal
	cmp #'<'
	beq .shift
	jsr push_source_byte
.single:
	lda #'<'
	sta currentTokenKind
	rts
.equal:
	lda #TOKEN_LE
	sta currentTokenKind
	rts
.shift:
	lda #TOKEN_SHL
	sta currentTokenKind
	rts
.noSecond:
	cmp #SOURCE_STATE_EOF
	beq .single
	lda #LEX_IO_ERROR
	jmp set_lex_error

scan_greater:
	jsr read_source_byte
	bcc .noSecond
	cmp #'='
	beq .equal
	cmp #'>'
	beq .shift
	jsr push_source_byte
.single:
	lda #'>'
	sta currentTokenKind
	rts
.equal:
	lda #TOKEN_GE
	sta currentTokenKind
	rts
.shift:
	lda #TOKEN_SHR
	sta currentTokenKind
	rts
.noSecond:
	cmp #SOURCE_STATE_EOF
	beq .single
	lda #LEX_IO_ERROR
	jmp set_lex_error

;;; Exactly one reusable current token.
currentTokenKind:	byte TOKEN_EOF
currentTokenType:	byte TOKEN_TYPE_NONE
currentTokenValue:	word 0
currentTokenLength:	byte 0
currentTokenLine:	word 1
currentTokenText:
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
	byte 0,0,0,0,0,0,0,0
scannerError:		byte LEX_OK

;;; Small scanner scratch; none of it survives as token history.
scanByte:		byte 0
scanDigit:		byte 0
scanTemp:		word 0
