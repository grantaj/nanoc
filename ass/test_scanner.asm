	include "zp.inc"
	include "../test.inc"

	* = TEST_ENTRY

main:
	;; Case 1: ordinary lexeme returns a source view and stops at whitespace.
	lda #<wordInput
	sta ZP_PTR1
	lda #>wordInput
	sta ZP_PTR1+1
	lda #<wordEnd
	sta sourceEnd
	lda #>wordEnd
	sta sourceEnd+1
	jsr scanLexeme

	cpx #$03
	bne .fail01
	lda ZP_PTR0
	cmp #<wordInput
	bne .fail02
	lda ZP_PTR0+1
	cmp #>wordInput
	bne .fail03
	lda ZP_PTR1
	cmp #<wordDelimiter
	bne .fail04
	lda ZP_PTR1+1
	cmp #>wordDelimiter
	bne .fail05
	lda wordInput
	cmp #'L'
	bne .fail06		; scanner must not modify source text

	;; Case 2: punctuation stays in the lexeme; NUL is only a delimiter.
	lda #<labelInput
	sta ZP_PTR1
	lda #>labelInput
	sta ZP_PTR1+1
	lda #<labelEnd
	sta sourceEnd
	lda #>labelEnd
	sta sourceEnd+1
	jsr scanLexeme

	cpx #$06
	bne .fail07
	lda ZP_PTR1
	cmp #<labelEol
	bne .fail08
	lda ZP_PTR1+1
	cmp #>labelEol
	bne .fail09

	;; Case 3: source and lexeme pointers cross a page boundary correctly.
	lda #<pageInput
	sta ZP_PTR1
	lda #>pageInput
	sta ZP_PTR1+1
	lda #<pageEnd
	sta sourceEnd
	lda #>pageEnd
	sta sourceEnd+1
	jsr scanLexeme

	cpx #$04
	bne .fail10
	lda ZP_PTR0
	cmp #<pageInput
	bne .fail11
	lda ZP_PTR0+1
	cmp #>pageInput
	bne .fail12
	lda ZP_PTR1
	cmp #<pageDelimiter
	bne .fail13
	lda ZP_PTR1+1
	cmp #>pageDelimiter
	bne .fail14

	;; Case 4: the explicit source end bounds scanning even without a delimiter.
	lda #<boundedInput
	sta ZP_PTR1
	lda #>boundedInput
	sta ZP_PTR1+1
	lda #<boundedEnd
	sta sourceEnd
	lda #>boundedEnd
	sta sourceEnd+1
	jsr scanLexeme

	cpx #$03
	bne .fail15
	lda ZP_PTR1
	cmp #<boundedEnd
	bne .fail16
	lda ZP_PTR1+1
	cmp #>boundedEnd
	bne .fail17

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
.fail10:
	lda #$0a
	jmp .finish
.fail11:
	lda #$0b
	jmp .finish
.fail12:
	lda #$0c
	jmp .finish
.fail13:
	lda #$0d
	jmp .finish
.fail14:
	lda #$0e
	jmp .finish
.fail15:
	lda #$0f
	jmp .finish
.fail16:
	lda #$10
	jmp .finish
.fail17:
	lda #$11

.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; scanner.asm expects the caller to own the source-end pointer.
sourceEnd:
	word 0

	include "scanner.asm"

	* = $c300
wordInput:
	byte 'L','D','A'
wordDelimiter:
	byte ' '
	byte '#','$','0','0',0
wordEnd:

labelInput:
	byte 'S','T','A','R','T',':'
labelEol:
	byte 0
labelEnd:

	* = $c3fd
pageInput:
	byte 'A','B','C','D'
pageDelimiter:
	byte ' '
pageEnd:

	* = $c500
boundedInput:
	byte 'X','Y','Z'
boundedEnd:
