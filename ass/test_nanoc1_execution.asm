	include "../test.inc"

;;; Execute one real nanoc1-generated program at $0800.
;;; The shell assembles that output using vasm and preloads its PRG alongside
;;; this caller. All assertions execute on the emulated 6510, not on the host.
;;; Keeping the driver at $0200 leaves the C program's $0800 code and $4800
;;; BSS undisturbed (the same low driver location as the bootstrap oracle).
	* = $0200

main:
	jsr $0800
	sta $03                         ; diagnostic low return byte
	stx $04                         ; diagnostic high return byte
	cmp #N1_EXPECT_LOW
	bne .wrong
	cpx #N1_EXPECT_HIGH
	bne .wrong
	lda #TEST_PASS
	jmp finish
.wrong:
	lda #$40
finish:
	sta TEST_RESULT
.halt:
	jmp .halt
