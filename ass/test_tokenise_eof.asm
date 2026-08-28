	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	;; Case 1: empty source is represented by start == end.
	lda #<emptyInput
	sta ZP_PTR1
	lda #>emptyInput
	sta ZP_PTR1+1
	lda #<emptyEnd
	sta sourceEnd
	lda #>emptyEnd
	sta sourceEnd+1
	jsr runTokenise

	lda ZP_PTR1
	cmp #<emptyEnd
	bne .fail01
	lda ZP_PTR1+1
	cmp #>emptyEnd
	bne .fail02
	jsr checkEmptyTokenStream
	bne .fail03

	;; Case 2: one comment-only source line consumes its EOL then reaches EOF.
	lda #<singleInput
	sta ZP_PTR1
	lda #>singleInput
	sta ZP_PTR1+1
	lda #<singleEnd
	sta sourceEnd
	lda #>singleEnd
	sta sourceEnd+1
	jsr runTokenise

	lda ZP_PTR1
	cmp #<singleEnd
	bne .fail04
	lda ZP_PTR1+1
	cmp #>singleEnd
	bne .fail05
	jsr checkEmptyTokenStream
	bne .fail06

	;; Case 3: consecutive blank lines are ordinary EOLs, not EOF.
	lda #<blankInput
	sta ZP_PTR1
	lda #>blankInput
	sta ZP_PTR1+1
	lda #<blankEnd
	sta sourceEnd
	lda #>blankEnd
	sta sourceEnd+1
	jsr runTokenise

	lda ZP_PTR1
	cmp #<blankEnd
	bne .fail07
	lda ZP_PTR1+1
	cmp #>blankEnd
	bne .fail08
	jsr checkEmptyTokenStream
	bne .fail09

	;; Case 4: whitespace before a final comment does not confuse EOL/EOF.
	lda #<whitespaceInput
	sta ZP_PTR1
	lda #>whitespaceInput
	sta ZP_PTR1+1
	lda #<whitespaceEnd
	sta sourceEnd
	lda #>whitespaceEnd
	sta sourceEnd+1
	jsr runTokenise

	lda ZP_PTR1
	cmp #<whitespaceEnd
	bne .fail0a
	lda ZP_PTR1+1
	cmp #>whitespaceEnd
	bne .fail0b
	jsr checkEmptyTokenStream
	bne .fail0c

	;; Case 5: scanning a comment across a page boundary advances both bytes.
	lda #<pageInput
	sta ZP_PTR1
	lda #>pageInput
	sta ZP_PTR1+1
	lda #<pageEnd
	sta sourceEnd
	lda #>pageEnd
	sta sourceEnd+1
	jsr runTokenise

	lda ZP_PTR1
	cmp #<pageEnd
	bne .fail0d
	lda ZP_PTR1+1
	cmp #>pageEnd
	bne .fail0e
	jsr checkEmptyTokenStream
	bne .fail0f

	lda #TEST_PASS
	jmp .finish

.fail01:
	lda #$01
	jmp .finish
.fail02:
	lda #$02
	jmp .finish
.fail03:
	lda #$03
	jmp .finish
.fail04:
	lda #$04
	jmp .finish
.fail05:
	lda #$05
	jmp .finish
.fail06:
	lda #$06
	jmp .finish
.fail07:
	lda #$07
	jmp .finish
.fail08:
	lda #$08
	jmp .finish
.fail09:
	lda #$09
	jmp .finish
.fail0a:
	lda #$0a
	jmp .finish
.fail0b:
	lda #$0b
	jmp .finish
.fail0c:
	lda #$0c
	jmp .finish
.fail0d:
	lda #$0d
	jmp .finish
.fail0e:
	lda #$0e
	jmp .finish
.fail0f:
	lda #$0f

.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; Run the tokeniser with a fresh output cursor.
runTokenise:
	lda #<testTokens
	sta ZP_PTR0
	lda #>testTokens
	sta ZP_PTR0+1
	jsr tokenise
	rts

;;; Comment/blank-line fixtures produce no tokens, only the stream EOF marker.
;;; Return Z set when the marker is exactly $00,$ff.
checkEmptyTokenStream:
	lda testTokens
	bne .bad
	lda testTokens+1
	cmp #$ff
	rts
.bad:
	lda #$01
	rts

	include "tokeniser.asm"

	* = $c400
emptyInput:
emptyEnd:

singleInput:
	string "; one source line"
singleEnd:

blankInput:
	string "; first line"
	byte 0			; blank line: creates two consecutive NULs
	string "; line after blank line"
	byte 0			; another blank line
blankEnd:

whitespaceInput:
	string "   \t ; final comment   "
whitespaceEnd:

	;; Place the final fixture close to a page boundary so comment scanning
	;; crosses from $c4ff to $c500.
	* = $c4fc
pageInput:
	string "; page crossing comment"
pageEnd:

	* = $c600
testTokens:
	byte 0,0
