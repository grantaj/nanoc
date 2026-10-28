	include "../test.inc"

; Small caller below the separate $0800-$9fff compiler image.
; The compiler's static C state is $a000-$cfff. The ordinary assembler,
; native bootstrap driver and their scratch memory are absent in this run.
	* = $0400
main:
	jsr $0800
	sta $03
	stx $04
	lda #TEST_PASS
	sta TEST_RESULT
.halt:
	jmp .halt
