\tinclude "../test.inc"

;;; Exercise a preloaded, production-generated nanoc1 at $4000. The harness
;;; observes A/X only; it does not duplicate scanner, parser or emitter logic.
\t* = ASSEMBLER_TEST_ENTRY

main:
\tjsr $4000
\tsta $03                 ; low return status for tests/run-test.sh
\tstx $04                 ; high return status
\tlda #TEST_PASS
\tsta TEST_RESULT
.halt:
\tjmp .halt
