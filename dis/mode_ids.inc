;;; Shared 6502 addressing-mode indexes.
;;; These indexes are the values stored in opcode_table and used to index
;;; the disassembler formatter table.

MODE_IMPLIED        = $00
MODE_ACCUMULATOR    = $01
MODE_IMMEDIATE      = $02
MODE_ZERO_PAGE      = $03
MODE_ZERO_PAGE_X    = $04
MODE_ZERO_PAGE_Y    = $05
MODE_ABSOLUTE       = $06
MODE_ABSOLUTE_X     = $07
MODE_ABSOLUTE_Y     = $08
MODE_INDIRECT       = $09
MODE_INDIRECT_X     = $0a
MODE_INDIRECT_Y     = $0b
MODE_RELATIVE       = $0c
MODE_UNDOCUMENTED   = $0d
