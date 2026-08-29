;;; Common convention for C64-native tests.
;;;
;;; A test writes TEST_RESULT exactly once when it has completed:
;;;   TEST_PASS ($ff) = success
;;;   any other value = test-specific failure code
;;;
;;; The host test runner watches TEST_RESULT for a store. The assertions
;;; themselves live entirely in 6502 code.
;;;
;;; A small test may simply run straight through its assertions. When named
;;; subtests make a larger test clearer, use this return convention:
;;;   carry set   = passed
;;;   carry clear = failed, with a FAIL_* code in A
;;;
;;; This is only a convention. Do not build an assertion framework around it.
;;;
;;; Ordinary tests start at $c000. Tests that include the complete assembler
;;; start at $4000 because the assembler no longer fits below the $d000 I/O
;;; window. Their output and symbol-table scratch remain below $4000.

TEST_RESULT          = $02
TEST_PASS            = $ff
TEST_ENTRY           = $c000
ASSEMBLER_TEST_ENTRY = $4000
