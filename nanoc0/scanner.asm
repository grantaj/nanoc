;;; scanner.asm
;;;
;;; Nano C Phase 1 source input and scanner.
;;;
;;; The input side reads directly from one C64 KERNAL sequential file.  It keeps
;;; only one scanner pushback byte; there is no source-file or source-line copy.
;;; CR and CRLF are normalised to one LF while reading so sourceLine counts
;;; physical lines consistently for C64, Unix and mixed test files.
;;;
;;; next_token replaces one reusable current-token record.  Identifiers and
;;; strings share the same fixed 64-byte text buffer.  Nothing allocates a token
;;; object or retains a token stream.

	include "../dis/kernal.inc"

SOURCE_LFN_DEFAULT       = 2
SOURCE_STATUS_EOI        = $40
SOURCE_STATE_OK          = 0
SOURCE_STATE_EOF         = 1
SOURCE_STATE_IO_ERROR    = 2
SOURCE_TAB               = $09
SOURCE_LF                = $0a
SOURCE_CR                = $0d

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

;;; open_source
;;; sourceName/sourceNameLength/sourceDevice identify the source file.
;;; Carry set means the KERNAL input channel is ready.
open_source:
	jsr close_source
	lda #SOURCE_STATE_OK
	sta sourceState
	lda #$00
	sta sourcePushbackValid
	sta sourceEofPending
	sta sourceSkipLf
	sta sourceLine+1
	lda #$01
	sta sourceLine

	jsr CLRCHN
	lda sourceNameLength
	ldx sourceName
	ldy sourceName+1
	jsr SETNAM
	lda sourceLfn
	ldx sourceDevice
	ldy sourceLfn
	jsr SETLFS
	jsr OPEN
	bcs .error
	lda #$01
	sta sourceOpen
	ldx sourceLfn
	jsr CHKIN
	bcc .ok
.error:
	;; CLOSE is harmless after a failed OPEN and also cleans up a CHKIN failure.
	jsr CLRCHN
	lda sourceLfn
	jsr CLOSE
	lda #$00
	sta sourceOpen
	lda #SOURCE_STATE_IO_ERROR
	sta sourceState
	clc
	rts
.ok:
	sec
	rts

;;; close_source
;;; Close only the logical file owned by this scanner.
close_source:
	lda sourceOpen
	beq .done
	jsr CLRCHN
	lda sourceLfn
	jsr CLOSE
	lda #$00
	sta sourceOpen
.done:
	rts

;;; read_source_byte
;;; Carry set: A is one source byte.
;;; Carry clear: sourceState says EOF or I/O error.
;;;
;;; One raw LF immediately following CR is discarded.  CR itself is returned as
;;; LF, so the scanner has one newline spelling and increments sourceLine once.
read_source_byte:
	lda sourcePushbackValid
	beq .notPushed
	lda #$00
	sta sourcePushbackValid
	lda sourcePushbackByte
	sec
	rts

.notPushed:
	lda sourceState
	cmp #SOURCE_STATE_OK
	beq .raw
	clc
	rts

.raw:
	lda sourceEofPending
	beq .read
	jsr close_source
	lda #SOURCE_STATE_EOF
	sta sourceState
	clc
	rts

.read:
	jsr CHRIN
	sta sourceByte
	jsr READST
	sta sourceKernalStatus

	;; EOI accompanies the final valid byte.  Any other status is an error.
	and #$bf
	beq .statusOk
	jsr close_source
	lda #SOURCE_STATE_IO_ERROR
	sta sourceState
	clc
	rts

.statusOk:
	lda sourceKernalStatus
	and #SOURCE_STATUS_EOI
	beq .haveByte
	lda #$01
	sta sourceEofPending

.haveByte:
	lda sourceSkipLf
	beq .normalise
	lda #$00
	sta sourceSkipLf
	lda sourceByte
	cmp #SOURCE_LF
	beq .raw			; discard the LF half of CRLF

.normalise:
	lda sourceByte
	cmp #SOURCE_CR
	bne .returnByte
	lda #$01
	sta sourceSkipLf
	lda #SOURCE_LF
.returnByte:
	sec
	rts

;;; push_source_byte
;;; The scanner never pushes more than the one byte it just looked at.
push_source_byte:
	sta sourcePushbackByte
	lda #$01
	sta sourcePushbackValid
	rts

increment_source_line:
	inc sourceLine
	bne .done
	inc sourceLine+1
.done:
	rts

;;; next_token
;;; Consume source bytes until one Phase 1 token replaces currentToken*.
next_token:
	lda #LEX_OK
	sta scannerError
.again:
	jsr read_source_byte
	bcs .haveByte
	lda sourceState
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
	bne .tokenStart
	jsr increment_source_line
	jmp .again

.tokenStart:
	sta scanByte
	jsr begin_current_token
	lda scanByte

	;; '/' exists in Phase 1 only as the opening half of a block comment.
	cmp #'/'
	bne .notSlash
	jsr read_source_byte
	bcs .slashSecond
	lda sourceState
	cmp #SOURCE_STATE_IO_ERROR
	bne .slashUnexpected
	jmp .ioError
.slashUnexpected:
	lda #LEX_UNEXPECTED_CHARACTER
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
	cmp #$27			; single quote
	bne .notCharacter
	jmp scan_character_literal
.notCharacter:
	cmp #$22
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
skip_block_comment:
.loop:
	jsr read_source_byte
	bcc .noByte
	cmp #SOURCE_LF
	bne .notLine
	jsr increment_source_line
	jmp .loop
.notLine:
	cmp #'*'
	bne .loop

.afterStar:
	jsr read_source_byte
	bcc .noByte
	cmp #SOURCE_LF
	bne .notLineAfterStar
	jsr increment_source_line
	jmp .loop
.notLineAfterStar:
	cmp #'/'
	beq .done
	cmp #'*'
	beq .afterStar
	jmp .loop

.noByte:
	lda sourceState
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
	lda sourceState
	cmp #SOURCE_STATE_EOF
	beq classify_identifier
	lda #LEX_IO_ERROR
	jmp set_lex_error

;;; classify_identifier
;;; The eight Phase 1 keywords live in one small length-prefixed table.  This
;;; avoids eight separate string-scanning paths while still comparing each
;;; identifier only once after it has been collected.
classify_identifier:
	ldx #$00
.nextKeyword:
	lda keywordTable,x
	beq .ordinary
	sta scanKeywordLength
	inx
	lda keywordTable,x
	sta scanKeywordKind
	inx
	txa
	clc
	adc scanKeywordLength
	sta scanKeywordNext

	lda scanKeywordLength
	cmp currentTokenLength
	bne .next
	ldy #$00
.compare:
	lda keywordTable,x
	cmp currentTokenText,y
	bne .next
	inx
	iny
	cpy scanKeywordLength
	bne .compare
	lda scanKeywordKind
	sta currentTokenKind
	rts
.next:
	ldx scanKeywordNext
	jmp .nextKeyword
.ordinary:
	lda #TOKEN_IDENTIFIER
	sta currentTokenKind
	rts

;;; Each entry is: text length, token kind, text bytes.  A zero length ends it.
keywordTable:
	byte 4,TOKEN_KW_CHAR,'c','h','a','r'
	byte 3,TOKEN_KW_INT,'i','n','t'
	byte 8,TOKEN_KW_UNSIGNED,'u','n','s','i','g','n','e','d'
	byte 2,TOKEN_KW_IF,'i','f'
	byte 4,TOKEN_KW_ELSE,'e','l','s','e'
	byte 5,TOKEN_KW_WHILE,'w','h','i','l','e'
	byte 5,TOKEN_KW_BREAK,'b','r','e','a','k'
	byte 6,TOKEN_KW_RETURN,'r','e','t','u','r','n'
	byte 0

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
	lda sourceState
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
	lda sourceState
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
	jsr push_source_byte
	lda #LEX_BAD_HEX
	jmp set_lex_error
.hexMissingSource:
	lda sourceState
	cmp #SOURCE_STATE_IO_ERROR
	beq .hexIo
	lda #LEX_BAD_HEX
	jmp set_lex_error
.hexEndSource:
	lda sourceState
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
	;; sum = old*10 + digit
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
;;; Carry set and A=0..15 for a hexadecimal digit; carry clear otherwise.
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
	bcs .haveFirst
	jmp .missingFirst
.haveFirst:
	cmp #SOURCE_LF
	bne .notLine
	jsr increment_source_line
	lda #LEX_UNTERMINATED_CHAR
	jmp set_lex_error
.notLine:
	cmp #$5c
	bne .notEscape
	lda #LEX_UNSUPPORTED_ESCAPE
	jmp set_lex_error
.notEscape:
	cmp #$27
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
	jsr increment_source_line
	lda #LEX_UNTERMINATED_CHAR
	jmp set_lex_error
.checkClose:
	cmp #$27
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
	lda sourceState
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
	jsr increment_source_line
	lda #LEX_UNTERMINATED_STRING
	jmp set_lex_error
.notLine:
	cmp #$5c
	bne .notEscape
	lda #LEX_UNSUPPORTED_ESCAPE
	jmp set_lex_error
.notEscape:
	cmp #$22
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
	lda sourceState
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
	lda sourceState
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
	lda sourceState
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
	lda sourceState
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
	lda sourceState
	cmp #SOURCE_STATE_EOF
	beq .single
	lda #LEX_IO_ERROR
	jmp set_lex_error

;;; Streaming source state.
sourceName:		word 0
sourceNameLength:	byte 0
sourceDevice:		byte 8
sourceLfn:		byte SOURCE_LFN_DEFAULT
sourceOpen:		byte 0
sourceState:		byte SOURCE_STATE_EOF
sourcePushbackValid:	byte 0
sourcePushbackByte:	byte 0
sourceEofPending:	byte 0
sourceSkipLf:		byte 0
sourceByte:		byte 0
sourceKernalStatus:	byte 0
sourceLine:		word 1

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
scanKeywordLength:	byte 0
scanKeywordKind:	byte 0
scanKeywordNext:	byte 0
