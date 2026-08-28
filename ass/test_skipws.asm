	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	;; Case 1: mixed spaces/tabs are skipped and registers are preserved.
	lda #<leadingWhitespace
	sta ZP_PTR1
	lda #>leadingWhitespace
	sta ZP_PTR1+1

	lda #$5a
	ldx #$3c
	ldy #$a5
	jsr skipWhitespace

	cmp #$5a
	bne .fail01
	cpx #$3c
	bne .fail02
	cpy #$a5
	bne .fail03
	lda ZP_PTR1
	cmp #<leadingExpected
	bne .fail04
	lda ZP_PTR1+1
	cmp #>leadingExpected
	bne .fail05

	;; Case 2: a non-whitespace first character is not consumed.
	lda #<noWhitespace
	sta ZP_PTR1
	lda #>noWhitespace
	sta ZP_PTR1+1
	jsr skipWhitespace

	lda ZP_PTR1
	cmp #<noWhitespace
	bne .fail06
	lda ZP_PTR1+1
	cmp #>noWhitespace
	bne .fail07

	;; Case 3: pointer advancement works across a page boundary.
	lda #<pageWhitespace
	sta ZP_PTR1
	lda #>pageWhitespace
	sta ZP_PTR1+1
	jsr skipWhitespace

	lda ZP_PTR1
	cmp #<pageExpected
	bne .fail08
	lda ZP_PTR1+1
	cmp #>pageExpected
	bne .fail09

	lda #TEST_PASS
	jmp .finish

.fail01:
	lda #$01		; A was not preserved
	jmp .finish
.fail02:
	lda #$02		; X was not preserved
	jmp .finish
.fail03:
	lda #$03		; Y was not preserved
	jmp .finish
.fail04:
	lda #$04		; wrong low pointer after whitespace
	jmp .finish
.fail05:
	lda #$05		; wrong high pointer after whitespace
	jmp .finish
.fail06:
	lda #$06		; consumed non-whitespace (low byte)
	jmp .finish
.fail07:
	lda #$07		; consumed non-whitespace (high byte)
	jmp .finish
.fail08:
	lda #$08		; page-crossing low byte wrong
	jmp .finish
.fail09:
	lda #$09		; page-crossing high byte wrong

.finish:
	;; This store is both the result and the completion signal observed by VICE.
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

	;; Start close enough to the page boundary that three whitespace bytes
	;; move the pointer from $c1ff to $c200.
	* = $c1fd
pageWhitespace:
	byte ' ', $09, ' '
pageExpected:
	byte 'Z', 0
