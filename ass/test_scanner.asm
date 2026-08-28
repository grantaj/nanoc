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
	beq .case1StartLow
	lda #$01
	jmp .finish
.case1StartLow:
	lda ZP_PTR0
	cmp #<wordInput
	beq .case1StartHigh
	lda #$02
	jmp .finish
.case1StartHigh:
	lda ZP_PTR0+1
	cmp #>wordInput
	beq .case1CursorLow
	lda #$03
	jmp .finish
.case1CursorLow:
	lda ZP_PTR1
	cmp #<wordDelimiter
	beq .case1CursorHigh
	lda #$04
	jmp .finish
.case1CursorHigh:
	lda ZP_PTR1+1
	cmp #>wordDelimiter
	beq .case1Source
	lda #$05
	jmp .finish
.case1Source:
	lda wordInput
	cmp #'L'
	beq .case2
	lda #$06		; scanner must not modify source text
	jmp .finish

.case2:
	;; Punctuation stays in the lexeme; NUL is only a delimiter.
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
	beq .case2CursorLow
	lda #$07
	jmp .finish
.case2CursorLow:
	lda ZP_PTR1
	cmp #<labelEol
	beq .case2CursorHigh
	lda #$08
	jmp .finish
.case2CursorHigh:
	lda ZP_PTR1+1
	cmp #>labelEol
	beq .case3
	lda #$09
	jmp .finish

.case3:
	;; Source and lexeme pointers cross a page boundary correctly.
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
	beq .case3StartLow
	lda #$0a
	jmp .finish
.case3StartLow:
	lda ZP_PTR0
	cmp #<pageInput
	beq .case3StartHigh
	lda #$0b
	jmp .finish
.case3StartHigh:
	lda ZP_PTR0+1
	cmp #>pageInput
	beq .case3CursorLow
	lda #$0c
	jmp .finish
.case3CursorLow:
	lda ZP_PTR1
	cmp #<pageDelimiter
	beq .case3CursorHigh
	lda #$0d
	jmp .finish
.case3CursorHigh:
	lda ZP_PTR1+1
	cmp #>pageDelimiter
	beq .case4
	lda #$0e
	jmp .finish

.case4:
	;; The explicit source end bounds scanning even without a delimiter.
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
	beq .case4CursorLow
	lda #$0f
	jmp .finish
.case4CursorLow:
	lda ZP_PTR1
	cmp #<boundedEnd
	beq .case4CursorHigh
	lda #$10
	jmp .finish
.case4CursorHigh:
	lda ZP_PTR1+1
	cmp #>boundedEnd
	beq .pass
	lda #$11
	jmp .finish

.pass:
	lda #TEST_PASS
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
