;;; assembler.asm
;;;
;;; Two direct walks over one source buffer.
;;;
;;; Pass 1 records labels/constants and advances the program counter without
;;; writing bytes. Pass 2 walks the same text again, verifies the layout, and
;;; streams bytes through emitInstruction.
;;;
;;; Input to assemble:
;;;   ZP_PTR1            source start
;;;   sourceEnd          one byte past source
;;;   assemblyPtr        first output/program address
;;;   symbolTableStart   caller-owned symbol-table memory
;;;   symbolTableLimit   first byte beyond that memory

PASS_LAYOUT = $01
PASS_EMIT   = $02

ASSEMBLE_OK              = $00
ASSEMBLE_BAD_STATEMENT   = $01
ASSEMBLE_BAD_SYMBOL      = $02
ASSEMBLE_SYMBOL_FULL     = $03
ASSEMBLE_SCOPE_ERROR     = $04
ASSEMBLE_BAD_INSTRUCTION = $05
ASSEMBLE_UNDEFINED       = $06
ASSEMBLE_EMIT_ERROR      = $07
ASSEMBLE_PHASE_ERROR     = $08

;;; assemble
;;; Pass-2 failure may leave earlier instructions already emitted.
assemble:
	lda ZP_PTR1
	sta assemblySource
	lda ZP_PTR1+1
	sta assemblySource+1
	lda assemblyPtr
	sta assemblyStart
	lda assemblyPtr+1
	sta assemblyStart+1

	jsr resetSymbols
	lda #PASS_LAYOUT
	jsr runAssemblyPass
	cmp #ASSEMBLE_OK
	bne .done
	lda assemblyPtr
	sta assemblyPassEnd
	lda assemblyPtr+1
	sta assemblyPassEnd+1

	;; Rewind source and program counter for the real emitting pass.
	lda assemblySource
	sta ZP_PTR1
	lda assemblySource+1
	sta ZP_PTR1+1
	lda assemblyStart
	sta assemblyPtr
	lda assemblyStart+1
	sta assemblyPtr+1
	lda #PASS_EMIT
	jsr runAssemblyPass
	cmp #ASSEMBLE_OK
	bne .done

	;; A source with no later label still needs this final phase check.
	lda assemblyPtr
	cmp assemblyPassEnd
	bne .phase
	lda assemblyPtr+1
	cmp assemblyPassEnd+1
	bne .phase
	lda #ASSEMBLE_OK
.done:
	rts
.phase:
	lda #ASSEMBLE_PHASE_ERROR
	rts

;;; runAssemblyPass
;;; A = PASS_LAYOUT or PASS_EMIT.
runAssemblyPass:
	sta assemblyPass
	lda #$00
	sta currentScope
.loop:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .done
	cmp #STATEMENT_LABEL
	beq .label
	cmp #STATEMENT_SYMBOL
	beq .symbol
	cmp #STATEMENT_INSTRUCTION
	beq .instruction
	lda #ASSEMBLE_BAD_STATEMENT
	rts
.label:
	jsr assembleLabel
	jmp .status
.symbol:
	jsr assembleSymbol
	jmp .status
.instruction:
	jsr assembleInstruction
.status:
	cmp #ASSEMBLE_OK
	beq .loop
	rts
.done:
	lda #ASSEMBLE_OK
	rts

;;; assembleLabel
;;; A global label starts a new local-label scope. Pass 1 records its address;
;;; pass 2 requires the same label to occur at the same address.
assembleLabel:
	jsr enterLabelScope
	bcc .scopeError

	lda statementName
	sta symbolName
	lda statementName+1
	sta symbolName+1
	lda statementNameLength
	sta symbolNameLength

	lda assemblyPass
	cmp #PASS_LAYOUT
	bne .verify
	lda assemblyPtr
	sta symbolValue
	lda assemblyPtr+1
	sta symbolValue+1
	jsr defineSymbol
	jmp mapSymbolStatus

.verify:
	jsr findSymbol
	bcc .undefined
	lda symbolValue
	cmp assemblyPtr
	bne .phase
	lda symbolValue+1
	cmp assemblyPtr+1
	bne .phase
	lda #ASSEMBLE_OK
	rts
.scopeError:
	lda #ASSEMBLE_SCOPE_ERROR
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts
.phase:
	lda #ASSEMBLE_PHASE_ERROR
	rts

;;; assembleSymbol
;;; `name = value` must already be resolvable when encountered on pass 1.
;;; Pass 2 simply confirms that it still has the same value.
assembleSymbol:
	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldx statementArgumentLength
	jsr parseValue
	cmp #VALUE_OK
	bne .bad

	lda statementName
	sta symbolName
	lda statementName+1
	sta symbolName+1
	lda statementNameLength
	sta symbolNameLength

	lda assemblyPass
	cmp #PASS_LAYOUT
	bne .verify
	lda valueResult
	sta symbolValue
	lda valueResult+1
	sta symbolValue+1
	jsr defineSymbol
	jmp mapSymbolStatus

.verify:
	jsr findSymbol
	bcc .bad
	lda symbolValue
	cmp valueResult
	bne .phase
	lda symbolValue+1
	cmp valueResult+1
	bne .phase
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_SYMBOL
	rts
.phase:
	lda #ASSEMBLE_PHASE_ERROR
	rts

;;; assembleInstruction
;;; Pass 1 only advances assemblyPtr. An unresolved short/long direct operand
;;; reserves the three-byte long form. Pass 2 requires resolution and emits.
assembleInstruction:
	jsr parseInstruction
	cmp #INSTRUCTION_OK
	bne .bad
	jsr resolveInstructionValue
	cmp #VALUE_BAD
	beq .bad

	;; CPX leaves the value status in A for the pass-2 unresolved check.
	ldx assemblyPass
	cpx #PASS_LAYOUT
	beq .layout
	cmp #VALUE_UNRESOLVED
	beq .undefined

	jsr emitInstruction
	cmp #EMIT_OK
	bne .emitError
	lda #ASSEMBLE_OK
	rts

.layout:
	lda instructionMode
	cmp #MODE_DEFERRED
	beq .long
	tay
	lda modeOperandWidths,y
	clc
	adc #$01			; operand bytes + opcode
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts
.long:
	lda #$03
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts

.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts
.emitError:
	lda #ASSEMBLE_EMIT_ERROR
	rts

;;; resolveInstructionValue
;;; The instruction parser keeps symbolic operand text in place. Resolve that
;;; text here; only a deferred direct operand needs a new short/long mode choice.
resolveInstructionValue:
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	beq .symbol
	lda #VALUE_OK
	rts

.symbol:
	lda instructionSymbol
	sta ZP_PTR0
	lda instructionSymbol+1
	sta ZP_PTR0+1
	ldx instructionSymbolLength
	jsr parseValue
	cmp #VALUE_OK
	beq .resolved
	rts

.resolved:
	lda valueResult
	sta instructionOperandValue
	lda valueResult+1
	sta instructionOperandValue+1
	lda #OPERAND_NUMBER
	sta instructionOperandKind

	lda instructionMode
	cmp #MODE_DEFERRED
	beq .direct
	cmp #MODE_RELATIVE
	beq .ok			; relative syntax names a 16-bit target address

	;; Every other one-byte operand must actually fit in one byte.
	tay
	lda modeOperandWidths,y
	cmp #$01
	bne .ok
	lda instructionOperandValue+1
	beq .ok
	jmp .bad

.direct:
	lda instructionOperandValue+1
	bne .long
	ldx instructionIndex
	lda directShortModes,x
	jsr tryMode
	bcs .ok
.long:
	ldx instructionIndex
	lda directLongModes,x
	jsr tryMode
	bcc .bad
.ok:
	lda #VALUE_OK
	rts
.bad:
	lda #VALUE_BAD
	rts

;;; enterLabelScope
;;; One byte is enough: each global label starts the scope used by following
;;; `.local` labels and references.
enterLabelScope:
	lda statementNameLength
	beq .bad
	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'.'
	beq .local
	inc currentScope
	beq .bad			; more than 255 global-label scopes
	sec
	rts
.local:
	lda currentScope
	beq .bad
	sec
	rts
.bad:
	clc
	rts

mapSymbolStatus:
	cmp #SYMBOL_OK
	beq .ok
	cmp #SYMBOL_FULL
	beq .full
	cmp #SYMBOL_NO_SCOPE
	beq .scope
	lda #ASSEMBLE_BAD_SYMBOL		; duplicate definition
	rts
.ok:
	lda #ASSEMBLE_OK
	rts
.full:
	lda #ASSEMBLE_SYMBOL_FULL
	rts
.scope:
	lda #ASSEMBLE_SCOPE_ERROR
	rts

;;; A = byte count. Advance the 16-bit program counter.
advanceAssemblyPtr:
	clc
	adc assemblyPtr
	sta assemblyPtr
	bcc .done
	inc assemblyPtr+1
.done:
	rts

assemblyPass:		byte 0
assemblySource:		word 0
assemblyStart:		word 0
assemblyPassEnd:	word 0
