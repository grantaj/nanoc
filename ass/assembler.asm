;;; assembler.asm
;;;
;;; Two passes over one source buffer. Pass 1 records symbols and layout;
;;; pass 2 resolves the same source and emits directly through emitInstruction.
;;;
;;; Input to assemble:
;;;   ZP_PTR1            source start
;;;   sourceEnd          one byte past source
;;;   assemblyPtr        first output/program address
;;;   symbolTableStart   caller-owned symbol-table memory
;;;   symbolTableLimit   first byte beyond that memory

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
;;;
;;; Pass 1 emits nothing. Pass 2 streams final bytes at assemblyPtr. A failure
;;; during pass 2 can therefore leave earlier instructions already emitted.
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
	lda #$01
	jsr runAssemblyPass
	cmp #ASSEMBLE_OK
	bne .done
	lda assemblyPtr
	sta assemblyPassEnd
	lda assemblyPtr+1
	sta assemblyPassEnd+1

	lda assemblySource
	sta ZP_PTR1
	lda assemblySource+1
	sta ZP_PTR1+1
	lda assemblyStart
	sta assemblyPtr
	lda assemblyStart+1
	sta assemblyPtr+1
	lda #$02
	jsr runAssemblyPass
	cmp #ASSEMBLE_OK
	bne .done
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
;;; A = 1 for layout/symbol collection, 2 for verify/emit.
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
;;; Global labels advance currentScope; `.local` labels stay in that scope.
;;; Pass 1 defines the label. Pass 2 verifies its recorded address.
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
	cmp #$01
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
;;; `name = value` must resolve on pass 1. Pass 2 re-evaluates it and checks
;;; that the value has not changed.
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
	cmp #$01
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
;;; Pass 1 counts bytes only. A still-unresolved zero-page/absolute choice is
;;; conservatively three bytes. Pass 2 requires resolution and emits directly.
assembleInstruction:
	jsr parseInstruction
	cmp #INSTRUCTION_OK
	bne .bad
	jsr resolveInstructionValue
	sta instructionValueStatus
	cmp #VALUE_BAD
	beq .bad
	lda assemblyPass
	cmp #$01
	bne .emit

	lda instructionMode
	cmp #MODE_DEFERRED
	beq .long
	tay
	lda modeOperandWidths,y
	clc
	adc #$01
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts
.long:
	lda #$03
	jsr advanceAssemblyPtr
	lda #ASSEMBLE_OK
	rts

.emit:
	lda instructionValueStatus
	cmp #VALUE_UNRESOLVED
	beq .undefined
	jsr emitInstruction
	cmp #EMIT_OK
	bne .emitError
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
;;; Resolve the parser's zero-copy symbolic value. Fixed addressing modes keep
;;; their opcode; MODE_DEFERRED makes the final short/long choice here.
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
	beq .ok			; branch value is a 16-bit target address
	cmp #MODE_IMMEDIATE
	beq .byte
	cmp #MODE_ZERO_PAGE
	beq .byte
	cmp #MODE_ZERO_PAGE_X
	beq .byte
	cmp #MODE_ZERO_PAGE_Y
	beq .byte
	cmp #MODE_INDIRECT_X
	beq .byte
	cmp #MODE_INDIRECT_Y
	beq .byte
	jmp .ok
.byte:
	lda instructionOperandValue+1
	beq .ok
	lda #VALUE_BAD
	rts
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
;;; One byte is enough: each global label starts a new local-label scope.
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
	beq .bad			; scope counter wrapped
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
	lda #ASSEMBLE_BAD_SYMBOL		; duplicate
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

;;; A = byte count; advance the 16-bit location counter.
advanceAssemblyPtr:
	clc
	adc assemblyPtr
	sta assemblyPtr
	bcc .done
	inc assemblyPtr+1
.done:
	rts

assemblyPass:		byte 0
instructionValueStatus:	byte 0
assemblySource:		word 0
assemblyStart:		word 0
assemblyPassEnd:	word 0
