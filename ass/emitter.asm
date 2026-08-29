;;; emitter.asm
;;;
;;; Emit one successfully parsed instruction directly to its final memory
;;; address. assemblyPtr is both the destination cursor and the current 6502
;;; program address; no separate location counter is kept.
;;;
;;; Input semantic state is produced by parseInstruction:
;;;   instructionOpcode
;;;   instructionMode
;;;   instructionOperandKind
;;;   instructionOperandValue
;;;
;;; emitInstruction output:
;;;   A             EMIT_* status
;;;   assemblyPtr   advanced by instruction size on success, unchanged on error
;;;
;;; Output memory is changed only on success. A, X, Y, ZP_PTR0 and flags are
;;; clobbered. ZP_PTR1 and the source buffer are preserved.

EMIT_OK           = $00
EMIT_UNRESOLVED   = $01
EMIT_BRANCH_RANGE = $02

;;; emitInstruction
;;;
;;; Write opcode and resolved operand bytes at assemblyPtr. Relative operands
;;; are target addresses and are converted to the 6502 signed byte displacement
;;; before any output is written.
emitInstruction:
	lda instructionMode
	cmp #MODE_DEFERRED
	beq .unresolved
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	beq .unresolved

	lda instructionMode
	cmp #MODE_RELATIVE
	beq .relative

	tay
	lda modeOperandWidths,y
	tax				; operand byte count

	lda assemblyPtr
	sta ZP_PTR0
	lda assemblyPtr+1
	sta ZP_PTR0+1
	ldy #$00
	lda instructionOpcode
	sta (ZP_PTR0),y

	cpx #$00
	beq .advance
	iny
	lda instructionOperandValue
	sta (ZP_PTR0),y
	cpx #$01
	beq .advance
	iny
	lda instructionOperandValue+1
	sta (ZP_PTR0),y		; 16-bit operands are little endian
	jmp .advance

.relative:
	jsr relativeOffset
	bcc .branchRange		; validate before changing output memory
	tax				; keep offset while loading the output pointer

	lda assemblyPtr
	sta ZP_PTR0
	lda assemblyPtr+1
	sta ZP_PTR0+1
	ldy #$00
	lda instructionOpcode
	sta (ZP_PTR0),y
	iny
	txa
	sta (ZP_PTR0),y

.advance:
	iny				; Y was operand width, now total instruction size
	tya
	clc
	adc assemblyPtr
	sta assemblyPtr
	bcc .ok
	inc assemblyPtr+1		; destination crossed a page
.ok:
	lda #EMIT_OK
	rts

.unresolved:
	lda #EMIT_UNRESOLVED
	rts

.branchRange:
	lda #EMIT_BRANCH_RANGE
	rts

;;; relativeOffset
;;;
;;; instructionOperandValue is the branch target and assemblyPtr is the branch
;;; opcode address. Compute target - (assemblyPtr + 2).
;;;
;;; Returns the signed offset byte in A with carry set when it fits -128..127.
;;; Carry is clear when out of range. A, X, ZP_PTR0 and flags are clobbered;
;;; Y and assemblyPtr are preserved.
relativeOffset:
	clc
	lda assemblyPtr
	adc #$02
	sta ZP_PTR0
	lda assemblyPtr+1
	adc #$00
	sta ZP_PTR0+1

	sec
	lda instructionOperandValue
	sbc ZP_PTR0
	tax				; low byte also contains the encoded offset
	lda instructionOperandValue+1
	sbc ZP_PTR0+1		; high byte must be sign extension of X

	cpx #$80
	bcc .positive
	cmp #$ff
	bne .outOfRange
	txa
	sec
	rts

.positive:
	cmp #$00
	bne .outOfRange
	txa
	sec
	rts

.outOfRange:
	clc
	rts

;;; Sole output/location state. The next emitted byte is written here.
assemblyPtr:
	word 0

	include "../dis/mode_widths.asm"
