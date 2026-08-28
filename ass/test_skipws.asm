	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	;; Case 1: mixed spaces/tabs are skipped; X is the promised preserved reg.
	lda #<leadingWhitespace
	sta ZP_PTR1
	lda #>leadingWhitespace
	sta ZP_PTR1+1
	ldx #$3c
	jsr skipWhitespace

	cpx #$3c
	beq .case1PointerLow
	lda #$01
	jmp .finish
.case1PointerLow:
	lda ZP_PTR1
	cmp #<leadingExpected
	beq .case1PointerHigh
	lda #$02
	jmp .finish
.case1PointerHigh:
	lda ZP_PTR1+1
	cmp #>leadingExpected
	beq .case2
	lda #$03
	jmp .finish

.case2:
	;; A non-whitespace first character is not consumed.
	lda #<noWhitespace
	sta ZP_PTR1
	lda #>noWhitespace
	sta ZP_PTR1+1
	jsr skipWhitespace

	lda ZP_PTR1
	cmp #<noWhitespace
	beq .case2PointerHigh
	lda #$04
	jmp .finish
.case2PointerHigh:
	lda ZP_PTR1+1
	cmp #>noWhitespace
	beq .case3
	lda #$05
	jmp .finish

.case3:
	;; Pointer advancement works across a page boundary.
	lda #<pageWhitespace
	sta ZP_PTR1
	lda #>pageWhitespace
	sta ZP_PTR1+1
	jsr skipWhitespace

	lda ZP_PTR1
	cmp #<pageExpected
	beq .case3PointerHigh
	lda #$06
	jmp .finish
.case3PointerHigh:
	lda ZP_PTR1+1
	cmp #>pageExpected
	beq .pass
	lda #$07
	jmp .finish

.pass:
	lda #TEST_PASS
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

	include "skipws.asm"

	* = $c100
leadingWhitespace:
	byte ' ', ' ', $09, ' '
leadingExpected:
	byte 'X', 0

noWhitespace:
	byte 'Y', 0

	* = $c1fd
pageWhitespace:
	byte ' ', $09, ' '
pageExpected:
	byte 'Z', 0
