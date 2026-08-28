;;; tokeniser.asm
;;;
;;; Tokenise an in-memory source buffer.
;;;
;;; Input contract:
;;;   ZP_PTR1 points to the current source byte.
;;;   sourceEnd contains the address one byte past the source buffer.
;;;   Source is represented as a sequence of NUL-terminated lines.
;;;   NUL means end-of-line only. EOF is ZP_PTR1 == sourceEnd.
;;;
;;; Output contract:
;;;   ZP_PTR0 points to the token output buffer.
;;;   EOF is written to the token stream as $00,$ff.
;;;
;;; The explicit end pointer keeps EOF independent of source contents, so
;;; blank lines (including consecutive blank lines) are unambiguous.

;;; Token types
LABEL     = 1
SYMBOL    = 2
DIRECTIVE = 3
MNEMONIC  = 4
OPERAND   = 5
EQUALS    = 6

tokenise:
	lda #$00
	sta prevTokenValid

.loop:
	;; EOF is the end address, not a sentinel byte in the source.
	lda ZP_PTR1
	cmp sourceEnd
	bne .haveSource
	lda ZP_PTR1+1
	cmp sourceEnd+1
	beq .eof

.haveSource:
	ldy #$00
	lda (ZP_PTR1),y
	beq .endOfLine

	jsr skipWhitespace

	;; Whitespace may have advanced us to the line terminator.
	ldy #$00
	lda (ZP_PTR1),y
	beq .endOfLine

	;; A semicolon comments out the remainder of the current line.
	cmp #';'
	beq .nextLine

.getTokenValue:
	tax			; X holds first character
	jsr getLexeme

	;; Token classification
	;;   X = first character
	;;   A = last character
.checkLabel:
	cpx #':'
	bne .checkDirective
	lda #DIRECTIVE
	sta (ZP_PTR0),y
	jmp .finishToken

.checkDirective:
	;; starts with a dot?
	cmp #'.'
	bne .checkEquals
	lda #DIRECTIVE
	sta (ZP_PTR0),y
	jmp .finishToken

.checkEquals:
	;; ends with equals?
	cpx #'='
	bne .mnemonicOrOperand
	lda #EQUALS
	sta (ZP_PTR0),y

	;; Previous token becomes a symbol when followed by equals.
	lda prevTokenValid
	beq .checkEqualsDone

	;; prevTokenType is an ordinary-memory pointer. 6502 indirect
	;; addressing requires the pointer itself to be in zero page, so
	;; temporarily borrow ZP_PTR0 while preserving the output pointer.
	lda ZP_PTR0
	pha
	lda ZP_PTR0+1
	pha
	lda prevTokenType
	sta ZP_PTR0
	lda prevTokenType+1
	sta ZP_PTR0+1
	ldy #$00
	lda #SYMBOL
	sta (ZP_PTR0),y
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0

.checkEqualsDone:
	jmp .finishToken

.mnemonicOrOperand:
	;; Read the previous token type through the stored pointer. Borrow
	;; ZP_PTR0 for the legal (zp),Y access and restore it afterwards.
	lda ZP_PTR0
	pha
	lda ZP_PTR0+1
	pha
	lda prevTokenType
	sta ZP_PTR0
	lda prevTokenType+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	tax
	pla
	sta ZP_PTR0+1
	pla
	sta ZP_PTR0
	txa
	cmp #MNEMONIC
	bne .operand
	lda #MNEMONIC
	sta (ZP_PTR0),y
	jmp .finishToken

.operand:
	lda #OPERAND
	sta (ZP_PTR0),y

.finishToken:
	lda ZP_PTR0
	sta prevTokenType
	lda ZP_PTR0+1
	sta prevTokenType+1
	lda #$01
	sta prevTokenValid

	inc ZP_PTR0
	bne .loop
	inc ZP_PTR0+1
	jmp .loop

.endOfLine:
	;; Consume exactly one line terminator. A blank line is therefore just
	;; another NUL byte and cannot be confused with EOF.
	inc ZP_PTR1
	bne .loop
	inc ZP_PTR1+1
	jmp .loop

.nextLine:
	;; Skip a comment without reading beyond the defined source region.
	lda ZP_PTR1
	cmp sourceEnd
	bne .readLineByte
	lda ZP_PTR1+1
	cmp sourceEnd+1
	beq .eof

.readLineByte:
	ldy #$00
	lda (ZP_PTR1),y
	beq .endOfLine

	inc ZP_PTR1
	bne .nextLine
	inc ZP_PTR1+1
	jmp .nextLine

.eof:
	;; Mark end of token stream with $00,$ff.
	ldy #$00
	lda #$00
	sta (ZP_PTR0),y
	inc ZP_PTR0
	bne .writeFF
	inc ZP_PTR0+1
.writeFF:
	lda #$ff
	sta (ZP_PTR0),y
	rts

;;; sourceEnd is a normal-memory pointer because both available C64 zero-page
;;; pointers are already used for source and token cursors.
sourceEnd:
	word 0

prevTokenType:
	word 0

prevTokenValid:
	byte 0

	include "skipws.asm"
	include "getLexeme.asm"
