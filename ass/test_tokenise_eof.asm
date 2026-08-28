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
	jsr checkCase
	beq .case2
	ora #$10		; $11..$13 identify case 1 failure
	jmp .finish

.case2:
	;; One comment-only source line consumes its EOL then reaches EOF.
	lda #<singleInput
	sta ZP_PTR1
	lda #>singleInput
	sta ZP_PTR1+1
	lda #<singleEnd
	sta sourceEnd
	lda #>singleEnd
	sta sourceEnd+1
	jsr runTokenise
	jsr checkCase
	beq .case3
	ora #$20		; $21..$23 identify case 2 failure
	jmp .finish

.case3:
	;; Consecutive blank lines are ordinary EOLs, not EOF.
	lda #<blankInput
	sta ZP_PTR1
	lda #>blankInput
	sta ZP_PTR1+1
	lda #<blankEnd
	sta sourceEnd
	lda #>blankEnd
	sta sourceEnd+1
	jsr runTokenise
	jsr checkCase
	beq .case4
	ora #$30		; $31..$33 identify case 3 failure
	jmp .finish

.case4:
	;; Whitespace before a final comment does not confuse EOL/EOF.
	lda #<whitespaceInput
	sta ZP_PTR1
	lda #>whitespaceInput
	sta ZP_PTR1+1
	lda #<whitespaceEnd
	sta sourceEnd
	lda #>whitespaceEnd
	sta sourceEnd+1
	jsr runTokenise
	jsr checkCase
	beq .case5
	ora #$40		; $41..$43 identify case 4 failure
	jmp .finish

.case5:
	;; Scanning a comment across a page boundary advances both pointer bytes.
	lda #<pageInput
	sta ZP_PTR1
	lda #>pageInput
	sta ZP_PTR1+1
	lda #<pageEnd
	sta sourceEnd
	lda #>pageEnd
	sta sourceEnd+1
	jsr runTokenise
	jsr checkCase
	beq .pass
	ora #$50		; $51..$53 identify case 5 failure
	jmp .finish

.pass:
	lda #TEST_PASS

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

;;; Verify the common postcondition for these no-token fixtures.
;;; Returns A = 0 on success, otherwise:
;;;   1 = source pointer low byte did not reach sourceEnd
;;;   2 = source pointer high byte did not reach sourceEnd
;;;   3 = token stream EOF marker was not $00,$ff
checkCase:
	lda ZP_PTR1
	cmp sourceEnd
	beq .checkHigh
	lda #$01
	rts
.checkHigh:
	lda ZP_PTR1+1
	cmp sourceEnd+1
	beq .checkTokens
	lda #$02
	rts
.checkTokens:
	lda testTokens
	bne .badTokens
	lda testTokens+1
	cmp #$ff
	bne .badTokens
	lda #$00
	rts
.badTokens:
	lda #$03
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
	byte ' ', ' ', ' ', $09, ' '
	string "; final comment   "
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
