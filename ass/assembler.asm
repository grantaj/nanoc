;;; assembler.asm
;;;
;;; Source is parsed exactly once.  Pass 1 consumes each statement into an
;;; almost-final staged machine image, an owned symbol table, and only the tiny
;;; holes whose values/layout are not yet known.  Later work is memory-only:
;;; relax zero-page choices until stable, resolve holes, then commit the image.
;;;
;;; `assemble` keeps the old in-memory source entry point for native unit tests;
;;; it no longer rewinds that source.  `assembleFile` is the production path and
;;; reads one line at a time through source.asm.

PASS_LAYOUT = $01			; retained names for older callers/tests
PASS_EMIT   = $02

ASSEMBLE_OK              = $00
ASSEMBLE_BAD_STATEMENT   = $01
ASSEMBLE_BAD_SYMBOL      = $02
ASSEMBLE_SYMBOL_FULL     = $03
ASSEMBLE_SCOPE_ERROR     = $04
ASSEMBLE_BAD_INSTRUCTION = $05
ASSEMBLE_UNDEFINED       = $06
ASSEMBLE_EMIT_ERROR      = $07
ASSEMBLE_PHASE_ERROR     = $08		; now only an internal-consistency status
ASSEMBLE_BAD_DATA        = $09
ASSEMBLE_BAD_ORIGIN      = $0a
ASSEMBLE_WORK_FULL       = $0b
ASSEMBLE_IO_ERROR        = $0c
ASSEMBLE_LINE_TOO_LONG   = $0d
ASSEMBLE_INCLUDE_DEPTH   = $0e

;;; assemble
;;; Consume the existing caller-owned [ZP_PTR1,sourceEnd) fixture once.  This is
;;; useful for native tests; production source should use assembleFile.
assemble:
	lda #$00
	sta sourceFileMode
	jsr beginAssembly
.loop:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq finishAssembly
	jsr processStatement
	cmp #ASSEMBLE_OK
	beq .loop
	rts

;;; assembleFile
;;; Inputs in addition to the normal assembly/workspace pointers:
;;;   sourceName/sourceNameLength, sourceDevice, sourceLineBuffer.
;;; The root and included files are read sequentially; source text never needs
;;; to coexist in RAM beyond the current NUL-terminated line.
assembleFile:
	lda #$01
	sta sourceFileMode
	jsr beginAssembly
	jsr openRootSource
	cmp #ASSEMBLE_OK
	bne .done
.read:
	jsr readSourceLine
	bcs .line
	cmp #ASSEMBLE_OK
	beq finishAssembly
	jmp .done
.line:
	jsr prepareSourceLine
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .read			; blank/comment-only line
	jsr processStatement
	cmp #ASSEMBLE_OK
	beq .read
	pha
	jsr closeSourceTree
	pla
.done:
	rts

;;; beginAssembly
;;; Reset only persistent assembly state.  assemblyPtr on entry is the default
;;; target origin; a leading `* = value` may replace it before any output.
beginAssembly:
	lda assemblyPtr
	sta assemblyStart
	lda assemblyPtr+1
	sta assemblyStart+1
	jsr resetSymbols
	jsr resetRepresentation
	lda #$00
	sta currentScope
	lda #$01
	sta originAllowed
	rts

;;; finishAssembly
;;; No source is touched beyond this point.  Validate definitions, relax layout,
;;; resolve every hole in staging, then and only then copy to target memory.
finishAssembly:
	jsr sealRepresentation
	jsr allLabelsDefined
	bcc .undefined
	jsr relaxLayout
	cmp #ASSEMBLE_OK
	bne .done
	jsr resolveAllHoles
	cmp #ASSEMBLE_OK
	bne .done
	jsr copyRepresentation
.done:
	rts
.undefined:
	lda #ASSEMBLE_UNDEFINED
	rts

;;; processStatement
;;; Reduce one transient parsed statement immediately to persistent machine state.
processStatement:
	cmp #STATEMENT_LABEL
	bne .notLabel
	jmp assembleLabel
.notLabel:
	cmp #STATEMENT_SYMBOL
	bne .notSymbol
	jmp assembleSymbol
.notSymbol:
	cmp #STATEMENT_INSTRUCTION
	beq .instructionPath
	lda #ASSEMBLE_BAD_STATEMENT
	rts

.instructionPath:
	jsr isIncludeStatement
	bcc .codeOrData
	lda sourceFileMode
	beq .badInclude
	jsr includeSource
	rts
.badInclude:
	lda #ASSEMBLE_BAD_STATEMENT
	rts
.codeOrData:
	lda #$00
	sta originAllowed
	jsr dataStatementKind
	beq .instruction
	jsr assembleData
	rts
.instruction:
	jsr assembleInstruction
	rts

;;; isIncludeStatement
;;; Carry set only for the bare lower-case vasm-oldstyle name `include`.
isIncludeStatement:
	lda statementNameLength
	cmp #$07
	bne .no
	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'i'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'n'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'c'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'l'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'u'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'d'
	bne .no
	iny
	lda (ZP_PTR0),y
	cmp #'e'
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; assembleLabel
;;; The symbol stores its conservative target address.  Layout passes derive the
;;; current/final value by subtracting earlier one-byte relaxations.
assembleLabel:
	jsr enterLabelScope
	bcc .scopeError
	lda statementName
	sta symbolName
	lda statementName+1
	sta symbolName+1
	lda statementNameLength
	sta symbolNameLength
	jsr defineLabel
	jmp mapSymbolStatus
.scopeError:
	lda #ASSEMBLE_SCOPE_ERROR
	rts

;;; assembleSymbol
;;; `* = value` fixes the one target origin before code/data.  Other definitions
;;; are fixed constants and must resolve immediately; they never participate in
;;; layout relaxation.
assembleSymbol:
	lda statementNameLength
	cmp #$01
	bne .constant
	lda statementName
	sta ZP_PTR0
	lda statementName+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'*'
	beq .origin
.constant:
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
	lda valueResult
	sta symbolValue
	lda valueResult+1
	sta symbolValue+1
	jsr defineSymbol
	jmp mapSymbolStatus
.origin:
	lda originAllowed
	beq .badOrigin
	lda #$00
	sta originAllowed
	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldx statementArgumentLength
	jsr parseValue
	cmp #VALUE_OK
	bne .badOrigin
	lda valueResult
	sta assemblyPtr
	sta assemblyStart
	lda valueResult+1
	sta assemblyPtr+1
	sta assemblyStart+1
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_SYMBOL
	rts
.badOrigin:
	lda #ASSEMBLE_BAD_ORIGIN
	rts

;;; assembleInstruction
;;; Parse once.  Fixed operands become bytes now; label-dependent operands keep
;;; only their compact captured recipe.  Relative instructions are holes even
;;; with numeric targets because their own final PC can move during relaxation.
assembleInstruction:
	jsr parseInstruction
	cmp #INSTRUCTION_OK
	beq .parsed
	jmp .bad
.parsed:
	lda instructionOperandKind
	cmp #OPERAND_SYMBOL
	beq .symbolic
	lda instructionMode
	cmp #MODE_RELATIVE
	beq .knownRelative
	jsr stageResolvedInstruction
	rts

.knownRelative:
	jsr captureFixedInstructionValue
	jsr stageRelativeHole
	rts

.symbolic:
	lda instructionSymbol
	sta ZP_PTR0
	lda instructionSymbol+1
	sta ZP_PTR0+1
	ldx instructionSymbolLength
	jsr captureValue
	cmp #VALUE_OK
	beq .fixedSymbol
	cmp #VALUE_UNRESOLVED
	beq .deferred
	cmp #VALUE_SYMBOL_FULL
	beq .symbolFull
	cmp #VALUE_SCOPE_ERROR
	beq .scope
	jmp .bad

.fixedSymbol:
	lda valueResult
	sta instructionOperandValue
	lda valueResult+1
	sta instructionOperandValue+1
	lda #OPERAND_NUMBER
	sta instructionOperandKind
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .fixedMode
	lda instructionIndex
	sta operandIndex
	jsr selectDirectMode
	cmp #INSTRUCTION_OK
	beq .fixedMode
	jmp .bad
.fixedMode:
	lda instructionMode
	cmp #MODE_RELATIVE
	beq .fixedRelative
	jsr stageResolvedInstruction
	rts
.fixedRelative:
	jsr captureFixedInstructionValue
	jsr stageRelativeHole
	rts

.deferred:
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .notDirect
	jmp stageDirectHole
.notDirect:
	cmp #MODE_RELATIVE
	bne .fixedWidthHole
	jmp stageRelativeHole
.fixedWidthHole:
	jsr stageValueHoleInstruction
	rts
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.symbolFull:
	lda #ASSEMBLE_SYMBOL_FULL
	rts
.scope:
	lda #ASSEMBLE_SCOPE_ERROR
	rts

;;; captureFixedInstructionValue
;;; Turn instructionOperandValue into the same tiny recipe shape used by holes.
captureFixedInstructionValue:
	lda #$00
	sta capturedHasSymbol
	sta capturedSymbol
	sta capturedSymbol+1
	sta capturedRelaxSafe
	lda instructionOperandValue
	sta capturedAddend
	lda instructionOperandValue+1
	sta capturedAddend+1
	lda #VALUE_PREFIX_NONE
	sta capturedPrefix
	rts

;;; stageResolvedInstruction
;;; Emit a fully fixed non-relative instruction to staging in final byte order.
stageResolvedInstruction:
	lda instructionMode
	cmp #MODE_RELATIVE
	beq .bad			; callers deliberately route relative through a hole
	tay
	lda modeOperandWidths,y
	sta instructionWidth
	cmp #$01
	bne .opcode
	lda instructionOperandValue+1
	bne .bad
.opcode:
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda instructionWidth
	beq .ok
	lda instructionOperandValue
	jsr stageByte
	bcc .full
	lda instructionWidth
	cmp #$01
	beq .ok
	lda instructionOperandValue+1
	jsr stageByte
	bcc .full
.ok:
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; stageValueHoleInstruction
;;; Fixed-width symbolic instruction: opcode is final, only operand byte(s) wait.
stageValueHoleInstruction:
	lda assemblyPtr
	sta holeAddress
	lda assemblyPtr+1
	sta holeAddress+1
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda stagingPtr
	sta holeStage
	lda stagingPtr+1
	sta holeStage+1
	ldy instructionMode
	lda modeOperandWidths,y
	cmp #$01
	beq .byte
	cmp #$02
	beq .word
	jmp .bad
.byte:
	lda #HOLE_VALUE_BYTE
	sta holeKind
	lda #$00
	sta holeExtra
	jsr stageByte
	bcc .full
	jsr appendHole
	bcc .full
	lda #ASSEMBLE_OK
	rts
.word:
	lda #HOLE_VALUE_WORD
	sta holeKind
	lda #$00
	sta holeExtra
	jsr stageByte
	bcc .full
	lda #$00
	jsr stageByte
	bcc .full
	jsr appendHole
	bcc .full
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; stageRelativeHole
;;; Relative width is fixed but its encoded byte uses the final relaxed PC.
stageRelativeHole:
	lda assemblyPtr
	sta holeAddress
	lda assemblyPtr+1
	sta holeAddress+1
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda stagingPtr
	sta holeStage
	lda stagingPtr+1
	sta holeStage+1
	lda #HOLE_RELATIVE
	sta holeKind
	lda #$00
	sta holeExtra
	jsr stageByte
	bcc .full
	jsr appendHole
	bcc .full
	lda #ASSEMBLE_OK
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; stageDirectHole
;;; The only layout-changing record.  Stage the legal long form and remember the
;;; corresponding short opcode; later passes may mark this record one byte short.
stageDirectHole:
	lda assemblyPtr
	sta holeAddress
	lda assemblyPtr+1
	sta holeAddress+1
	lda stagingPtr
	sta holeStage
	lda stagingPtr+1
	sta holeStage+1

	ldx instructionIndex
	lda directShortModes,x
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .bad
	sta holeExtra

	ldx instructionIndex
	lda directLongModes,x
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .bad
	sta longOpcode
	lda #HOLE_DIRECT
	sta holeKind

	lda longOpcode
	jsr stageByte
	bcc .full
	lda #$00
	jsr stageByte
	bcc .full
	lda #$00
	jsr stageByte
	bcc .full
	jsr appendHole
	bcc .full
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; enterLabelScope
;;; Each global label starts the one-byte scope used by following `.local` names.
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
	beq .bad
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
	lda #ASSEMBLE_BAD_SYMBOL
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

sourceFileMode:	byte 0
originAllowed:	byte 0
assemblyStart:	word 0
instructionWidth:	byte 0
longOpcode:	byte 0

	include "capture.asm"
	include "representation.asm"
	include "source.asm"
	include "data.asm"
