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
;;;   A                       statement type
;;;   statementName          pointer to statement name
;;;   statementNameLength    name length
;;;   statementArgument      pointer to argument text, when present
;;;   statementArgumentLength argument length, with surrounding whitespace
;;;                           excluded
;;;
;;; On return ZP_PTR1 points to the start of the next source line or sourceEnd.

STATEMENT_EOF         = 0
STATEMENT_LABEL       = 1
STATEMENT_SYMBOL      = 2
STATEMENT_DIRECTIVE   = 3
STATEMENT_INSTRUCTION = 4

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
	beq .eof

	jsr skipWhitespace
	jsr sourceAtEnd
	beq .eof

	ldy #$00
	lda (ZP_PTR1),y
	beq .blankLine
	cmp #';'
	beq .commentLine

	jsr scanLexeme
	lda ZP_PTR0
	sta statementName
	lda ZP_PTR0+1
	sta statementName+1
	stx statementNameLength

	;; A leading dot identifies a directive. The semantic name excludes it.
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'.'
	beq .directive

	;; A trailing colon identifies a label. The semantic name excludes it.
	txa
	tay
	dey
	lda (ZP_PTR0),y
	cmp #':'
	beq .label

	;; Otherwise the first lexeme is either a symbol name or a mnemonic.
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

.directive:
	inc statementName
	bne .directiveNameReady
	inc statementName+1
.directiveNameReady:
	dec statementNameLength
	jsr scanArgument
	lda #STATEMENT_DIRECTIVE
	rts

.label:
	dec statementNameLength
	jsr skipRestOfLine
	lda #STATEMENT_LABEL
	rts

.blankLine:
	jsr advanceSource		; consume NUL EOL
	jmp .nextLine

.commentLine:
	jsr skipRestOfLine
	jmp .nextLine

.eof:
	lda #STATEMENT_EOF
	rts

;;; scanArgument
;;;
;;; Capture the remainder of the current line as a zero-copy argument view.
;;; Leading and trailing spaces/tabs are excluded. Embedded whitespace is kept.
;;; A comment ends the argument. The source cursor is advanced to the next line.
scanArgument:
	lda #$00
	sta statementArgumentLength

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
	beq .comment

	cmp #' '
	beq .advance
	cmp #$09
	beq .advance

	;; Keep the extent through the most recent non-whitespace byte. This trims
	;; only trailing whitespace without copying or rescanning the argument.
	txa
	clc
	adc #$01
	sta statementArgumentLength

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
;;;
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

;;; End of the caller-owned source region.
sourceEnd:
	word 0

	include "skipws.asm"
	include "scanner.asm"
