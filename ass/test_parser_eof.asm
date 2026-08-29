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
	jsr nextStatement
	jsr checkCase
	beq .case2
	ora #$10
	jmp .finish

.case2:
	;; A comment-only line is skipped before EOF is returned.
	lda #<singleInput
	sta ZP_PTR1
	lda #>singleInput
	sta ZP_PTR1+1
	lda #<singleEnd
	sta sourceEnd
	lda #>singleEnd
	sta sourceEnd+1
	jsr nextStatement
	jsr checkCase
	beq .case3
	ora #$20
	jmp .finish

.case3:
	;; Consecutive blank lines remain ordinary EOLs, not EOF.
	lda #<blankInput
	sta ZP_PTR1
	lda #>blankInput
	sta ZP_PTR1+1
	lda #<blankEnd
	sta sourceEnd
	lda #>blankEnd
	sta sourceEnd+1
	jsr nextStatement
	jsr checkCase
	beq .case4
	ora #$30
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
	jsr nextStatement
	jsr checkCase
	beq .case5
	ora #$40
	jmp .finish

.case5:
	;; Skipping a comment across a page boundary advances both pointer bytes.
	lda #<pageInput
	sta ZP_PTR1
	lda #>pageInput
	sta ZP_PTR1+1
	lda #<pageEnd
	sta sourceEnd
	lda #>pageEnd
	sta sourceEnd+1
	jsr nextStatement
	jsr checkCase
	beq .case6
	ora #$50
	jmp .finish

.case6:
	;; A label consumes only itself. The following statement on the same line
	;; must be returned by the next call rather than discarded with the line.
	lda #<inlineInput
	sta ZP_PTR1
	lda #>inlineInput
	sta ZP_PTR1+1
	lda #<inlineEnd
	sta sourceEnd
	lda #>inlineEnd
	sta sourceEnd+1

	jsr nextStatement
	cmp #STATEMENT_LABEL
	beq .inlineLabelTypeOk
	lda #$61
	jmp .finish
.inlineLabelTypeOk:
	lda statementName
	cmp #<inlineLabel
	beq .inlineLabelLowOk
	lda #$62
	jmp .finish
.inlineLabelLowOk:
	lda statementName+1
	cmp #>inlineLabel
	beq .inlineLabelHighOk
	lda #$63
	jmp .finish
.inlineLabelHighOk:
	lda statementNameLength
	cmp #$04
	beq .inlineStatement
	lda #$64
	jmp .finish

.inlineStatement:
	jsr nextStatement
	cmp #STATEMENT_INSTRUCTION
	beq .inlineTypeOk
	lda #$65
	jmp .finish
.inlineTypeOk:
	lda statementName
	cmp #<inlineWord
	beq .inlineNameLowOk
	lda #$66
	jmp .finish
.inlineNameLowOk:
	lda statementName+1
	cmp #>inlineWord
	beq .inlineNameHighOk
	lda #$67
	jmp .finish
.inlineNameHighOk:
	lda statementNameLength
	cmp #$04
	beq .inlineArgPtr
	lda #$68
	jmp .finish
.inlineArgPtr:
	lda statementArgument
	cmp #<inlineArgument
	bne .inlineArgBad
	lda statementArgument+1
	cmp #>inlineArgument
	bne .inlineArgBad
	lda statementArgumentLength
	cmp #$01
	beq .inlineEof
.inlineArgBad:
	lda #$69
	jmp .finish

.inlineEof:
	jsr nextStatement
	jsr checkCase
	beq .pass
	lda #$6a
	jmp .finish

.pass:
	lda #TEST_PASS
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; Verify EOF and the final source cursor.
;;; Returns A = 0 on success, otherwise:
;;;   1 = nextStatement did not return STATEMENT_EOF
;;;   2 = source pointer low byte did not reach sourceEnd
;;;   3 = source pointer high byte did not reach sourceEnd
checkCase:
	cmp #STATEMENT_EOF
	beq .checkLow
	lda #$01
	rts
.checkLow:
	lda ZP_PTR1
	cmp sourceEnd
	beq .checkHigh
	lda #$02
	rts
.checkHigh:
	lda ZP_PTR1+1
	cmp sourceEnd+1
	beq .ok
	lda #$03
	rts
.ok:
	lda #$00
	rts

	include "parser.asm"

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

inlineInput:
inlineLabel:
	byte 'd','a','t','a',':',' '
inlineWord:
	byte 'w','o','r','d',' '
inlineArgument:
	byte '0',0
inlineEnd:

	;; Place the final fixture close to a page boundary so comment scanning
	;; crosses from $c4ff to $c500.
	* = $c4fc
pageInput:
	string "; page crossing comment"
pageEnd:
