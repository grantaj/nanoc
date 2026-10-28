	include "../test.inc"

;;; Exercise a preloaded, production-generated nanoc1 at $4000. The harness
;;; observes A/X only; it does not duplicate scanner, parser or emitter logic.
    ifdef NANOC_LARGE_SEED
        * = $0200        ; development BSS begins at $0800
    else
        * = $0800        ; strict native compiler still uses old map
    endif

main:
	jsr $4000
	sta $03                 ; low return status for tests/run-test.sh
	stx $04                 ; high return status
	lda #TEST_PASS
	sta TEST_RESULT
.halt:
	jmp .halt
