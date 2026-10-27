	include "../test.inc"

;;; Exercise a preloaded, production-generated nanoc1 at $4000. The harness
;;; observes A/X only; it does not duplicate scanner, parser or emitter logic.
	* = $0800             ; small caller below the compiler at $4000

main:
	jsr $4000
	sta $03                 ; low return status for tests/run-test.sh
	stx $04                 ; high return status
	lda #TEST_PASS
	sta TEST_RESULT
.halt:
	jmp .halt
