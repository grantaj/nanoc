;;; selfhost_smoke.asm
;;; Tiny program assembled by the ass-built assembler during the self-host test.

start:
	lda #$2a
	sta $d020
	rts
