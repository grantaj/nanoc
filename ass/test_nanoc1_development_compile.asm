	include "../test.inc"

; Small caller below the separate $4000-$cfff compiler image.
; The compiler's static C state is $0800-$3fff. The ordinary assembler,
; native bootstrap driver and their scratch memory are absent in this run.
	* = $0400
main:
	jsr $4000
	sta $03
	stx $04
	lda #TEST_PASS
	sta TEST_RESULT
.halt:
	jmp .halt
