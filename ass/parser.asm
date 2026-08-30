;;; parser.asm
;;;
;;; Parse one assembler statement at a time directly from the source buffer.
;;; Lexeme text remains in the original source; statementName and
;;; statementArgument are transient pointer/length views overwritten by the
;;; next call to nextStatement.
;;;
;;; Input:
;;;   ZP_PTR1   current source cursor
;;;   sourceEnd one byte past the source buffer
;;;
;;; Output from nextStatement:
;;;   A                        statement type
;;;   statementName           pointer to statement name
;;;   statementNameLength     name length
;;;   statementArgument       pointer to argument text, when present
;;;   statementArgumentLength argument length, with surrounding whitespace
;;;                            excluded
;;;
;;; A label consumes only its own lexeme. If more text follows the colon on the
;;; same source line, the next call returns that statement. Other statements
;;; consume the rest of their line.

STATEMENT_EOF         = 0
STATEMENT_LABEL       = 1
STATEMENT_SYMBOL      = 2
STATEMENT_INSTRUCTION = 3

;;; nextStatement
;;;
;;; Blank and comment-only lines are skipped internally.
;;; A, X, Y and flags are clobbered.
nextStatement:
	lda #$00
	sta statementNameLength
	sta statementArgumentLength

.nextLine:
	jsr sourceAtEnd
	bne .haveSource
	lda #STATEMENT_EOF
	rts

.haveSource:
	jsr skipWhitespace
	jsr sourceAtEnd
	bne .readFirstByte
	lda #STATEMENT_EOF
	rts

.readFirstByte:
	ldy #$00
	lda (ZP_PTR1),y
	bne .notBlank
	jsr advanceSource		; consume NUL EOL
	jmp .nextLine

.notBlank:
	cmp #';'
	bne .statement
	jsr skipRestOfLine
	jmp .nextLine

.statement:
	jsr scanLexeme
	lda ZP_PTR0
	sta statementName
	lda ZP_PTR0+1
	sta statementName+1
	stx statementNameLength

	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #':'
	bne .notLabel
	jmp .label

.notLabel:
	;; Otherwise the first lexeme is either a symbol name or an instruction-like
	;; statement name. Bare pseudo-operations such as byte and word use this same
	;; path; their meaning belongs to the assembler, not the parser.
	jsr sourceAtEnd
	beq .instruction
	jsr skipWhitespace
	jsr sourceAtEnd
	beq .instruction
	ldy #$00
	lda (ZP_PTR1),y
	cmp #'='
	beq .symbol

.instruction:
	jsr scanArgument
	lda #STATEMENT_INSTRUCTION
	rts

.symbol:
	jsr advanceSource		; consume '='
	jsr scanArgument
	lda #STATEMENT_SYMBOL
	rts

.label:
	dec statementNameLength
	lda #STATEMENT_LABEL
	rts

;;; scanArgument
;;;
;;; Capture the remainder of the current line as a zero-copy argument view.
;;; Leading and trailing spaces/tabs are excluded. Embedded whitespace is kept.
;;; A semicolon ends the argument only outside single or double quotes. The
;;; source cursor is advanced to the next line. There are no escapes.
scanArgument:
	lda #$00
	sta statementArgumentLength
	sta argumentQuote

	jsr sourceAtEnd
	beq .atEnd
	jsr skipWhitespace

	lda ZP_PTR1
	sta statementArgument
	lda ZP_PTR1+1
	sta statementArgument+1

	ldx #$00
	ldy #$00

.loop:
	jsr sourceAtEnd
	beq .done

	lda (ZP_PTR1),y
	beq .endOfLine
	cmp #';'
	bne .maybeQuote
	lda argumentQuote
	beq .comment
	jmp .nonWhitespace

.maybeQuote:
	cmp #39				; single quote
	beq .quote
	cmp #34				; double quote
	bne .whitespace

.quote:
	lda argumentQuote
	beq .openQuote
	cmp (ZP_PTR1),y
	bne .nonWhitespace
	lda #$00
	sta argumentQuote
	jmp .nonWhitespace

.openQuote:
	lda (ZP_PTR1),y
	sta argumentQuote

.nonWhitespace:
	;; Keep the extent through the most recent non-whitespace byte. This trims
	;; only trailing whitespace without copying or rescanning the argument.
	txa
	clc
	adc #$01
	sta statementArgumentLength
	jmp .advance

.whitespace:
	cmp #' '
	beq .advance
	cmp #$09
	beq .advance
	jmp .nonWhitespace

.advance:
	inx
	jsr advanceSource
	jmp .loop

.comment:
	jsr skipRestOfLine
	rts

.endOfLine:
	jsr advanceSource
.done:
	rts

.atEnd:
	lda ZP_PTR1
	sta statementArgument
	lda ZP_PTR1+1
	sta statementArgument+1
	rts

;;; skipRestOfLine
;;; Advances over the remainder of the current line, including its NUL EOL.
;;; Stops at sourceEnd if no EOL remains.
skipRestOfLine:
	ldy #$00

.loop:
	jsr sourceAtEnd
	beq .done
	lda (ZP_PTR1),y
	beq .consumeEol
	jsr advanceSource
	jmp .loop

.consumeEol:
	jsr advanceSource
.done:
	rts

;;; Transient views produced by nextStatement.
statementName:
	word 0
statementNameLength:
	byte 0
statementArgument:
	word 0
statementArgumentLength:
	byte 0

;; scanArgument scratch. Zero means outside quotes; otherwise stores ' or ".
argumentQuote:
	byte 0

;;; End of the caller-owned source region.
sourceEnd:
	word 0

	include "skipws.asm"
	include "scanner.asm"
