;;; interface.inc
;;;
;;; Native command block for the assembly-written Phase 1 compiler.
;;;
;;; The caller owns the filename bytes. Source is read from device 8; generated
;;; ass source is written to device 9. The output name is a C64 KERNAL filename,
;;; so callers that create a sequential file include the usual ",S,W" suffix.
;;;
;;; On return, STATUS gives the broad failing layer, DETAIL gives that layer's
;;; small native error code, and LINE gives the current source line. BSS_BYTES is
;;; the generated program's final NC_BSS consumption.

NANOC_COMMAND_SOURCE        = $3000 ; word: source filename pointer
NANOC_COMMAND_SOURCE_LENGTH = $3002 ; byte
NANOC_COMMAND_OUTPUT        = $3003 ; word: output filename pointer
NANOC_COMMAND_OUTPUT_LENGTH = $3005 ; byte
NANOC_COMMAND_STATUS        = $3006 ; byte: NANOC_STATUS_*
NANOC_COMMAND_LINE          = $3007 ; word
NANOC_COMMAND_DETAIL        = $3009 ; byte: scanner/parser/expression detail
NANOC_COMMAND_BSS_BYTES     = $300a ; word

NANOC_STATUS_OK         = 0
NANOC_STATUS_SOURCE     = 1
NANOC_STATUS_OUTPUT     = 2
NANOC_STATUS_SCANNER    = 3
NANOC_STATUS_PARSER     = 4
NANOC_STATUS_EXPRESSION = 5
NANOC_STATUS_EMIT       = 6
NANOC_STATUS_LAYOUT     = 7
