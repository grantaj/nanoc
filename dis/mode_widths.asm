;;; Operand bytes for each shared 6502 addressing-mode index.
;;; Keep this table in MODE_* order from mode_ids.inc.
;;; MODE_UNDOCUMENTED is an unknown-opcode fallback, not a real instruction
;;; width: undocumented 6502 opcodes have varying operand sizes.

modeOperandWidths:
	byte 0		; MODE_IMPLIED
	byte 0		; MODE_ACCUMULATOR
	byte 1		; MODE_IMMEDIATE
	byte 1		; MODE_ZERO_PAGE
	byte 1		; MODE_ZERO_PAGE_X
	byte 1		; MODE_ZERO_PAGE_Y
	byte 2		; MODE_ABSOLUTE
	byte 2		; MODE_ABSOLUTE_X
	byte 2		; MODE_ABSOLUTE_Y
	byte 2		; MODE_INDIRECT
	byte 1		; MODE_INDIRECT_X
	byte 1		; MODE_INDIRECT_Y
	byte 1		; MODE_RELATIVE
	byte 0		; MODE_UNDOCUMENTED fallback
