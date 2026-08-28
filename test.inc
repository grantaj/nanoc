;;; Common convention for C64-native tests.
;;;
;;; A test writes TEST_RESULT exactly once when it has completed:
;;;   TEST_PASS ($ff) = success
;;;   any other value = test-specific failure code
;;;
;;; The host test runner watches TEST_RESULT for a store. The assertions
;;; themselves live entirely in 6502 code.

TEST_RESULT = $02
TEST_PASS   = $ff
TEST_ENTRY  = $c000
