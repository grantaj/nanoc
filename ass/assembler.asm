;;; assembler.asm
;;;
;;; Source is parsed exactly once. Each statement immediately contributes
;;; final-size machine bytes to staging and owned names to the symbol table.
;;; Plain unresolved 16-bit label references chain through their own operand
;;; bytes; exceptional one-byte/expression references use small fixup records.
;;; When a label appears, every reference waiting for it is patched immediately.
;;; EOF only validates that nothing remains undefined and commits the staged image.
;;;
;;; `assemble` keeps the in-memory source entry point for native unit tests.
;;; `assembleFile` is the production path and reads one line at a time through
;;; source.asm.

ASSEMBLE_OK              = $00
ASSEMBLE_BAD_STATEMENT   = $01
ASSEMBLE_BAD_SYMBOL      = $02
ASSEMBLE_SYMBOL_FULL     = $03
ASSEMBLE_SCOPE_ERROR     = $04
ASSEMBLE_BAD_INSTRUCTION = $05
ASSEMBLE_UNDEFINED       = $06
ASSEMBLE_EMIT_ERROR      = $07
ASSEMBLE_BAD_DATA        = $09
ASSEMBLE_BAD_ORIGIN      = $0a
ASSEMBLE_WORK_FULL       = $0b
ASSEMBLE_IO_ERROR        = $0c
ASSEMBLE_LINE_TOO_LONG   = $0d
ASSEMBLE_INCLUDE_DEPTH   = $0e

;;; Representation constants are needed by the orchestration below. Keeping
;;; representation.asm here also means ass never needs forward constant
;;; definitions merely because of source-file ordering.
	include "representation.asm"

;;; assemble
;;; Consume the existing caller-owned [ZP_PTR1,sourceEnd) fixture once. This is
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
;;; to coexist in RAM beyond the current NUL-terminated line. A label may be
;;; followed by another statement on that same line, so exhaust the line before
;;; asking the KERNAL reader for another one.
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
.statement:
	jsr nextStatement
	cmp #STATEMENT_EOF
	beq .read
	jsr processStatement
	cmp #ASSEMBLE_OK
	beq .statement
	pha
	jsr closeSourceTree
	pla
.done:
	rts

;;; beginAssembly
;;; Reset only persistent assembly state. assemblyPtr on entry is the default
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
;;; All widths and defined-symbol references are already final. Do not touch the
;;; target region until every forward name and exceptional fixup has disappeared.
finishAssembly:
	jsr sealRepresentation
	jsr allLabelsDefined
	bcc .undefined
	jsr allFixupsResolved
	bcc .undefined
	jsr copyRepresentation
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

	;; Include path construction borrows ZP_PTR1. Preserve the parser cursor so
	;; the caller can continue the current line after includeSource returns.
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha
	jsr includeSource
	tax
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	txa
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
;;; A label's address is final when it appears. Define it, immediately patch the
;;; plain word-reference chain, then resolve any exceptional fixups for it.
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
	cmp #SYMBOL_OK
	beq .defined
	jmp mapSymbolStatus
.defined:
	jsr resolveWordReferencesForSymbol
	jsr resolveSymbolFixups
	rts
.scopeError:
	lda #ASSEMBLE_SCOPE_ERROR
	rts

;;; assembleSymbol
;;; `* = value` fixes the one target origin before code/data. Other definitions
;;; are fixed constants and must resolve immediately.
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
	jsr defineConstant
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
;;; Parse once. Numeric values and already-defined labels are emitted immediately.
;;; Undefined labels either use the two-byte operand-chain trick or one small
;;; exceptional fixup when the encoded field is only one byte / has an addend.
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
	jsr stageResolvedRelative
	rts

.symbolic:
	lda instructionSymbol
	sta ZP_PTR0
	lda instructionSymbol+1
	sta ZP_PTR0+1
	ldx instructionSymbolLength
	jsr parseValue
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
	jsr stageResolvedRelative
	rts

.deferred:
	lda instructionMode
	cmp #MODE_DEFERRED
	bne .notDirect
	jmp stageDeferredDirect
.notDirect:
	cmp #MODE_RELATIVE
	bne .fixedWidth
	jmp stageRelativeFixup
.fixedWidth:
	jsr stageSymbolicInstruction
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

;;; isPlainLabelValue
;;; Carry set only for the common exact 16-bit value `label`. Expressions and
;;; byte-selection prefixes need their own small fixup.
isPlainLabelValue:
	lda capturedHasSymbol
	beq .no
	lda capturedPrefix
	bne .no
	lda capturedAddend
	ora capturedAddend+1
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; stagePlainWordReference
;;; Stage two bytes for an unresolved exact label address and link them through
;;; that label's symbol entry. The bytes are patched as soon as the label appears.
;;; Carry set on success, clear if staging is full.
stagePlainWordReference:
	lda stagingPtr
	sta referencePtr
	lda stagingPtr+1
	sta referencePtr+1
	lda #$00
	jsr stageByte
	bcc .full
	lda #$00
	jsr stageByte
	bcc .full
	lda capturedSymbol
	sta symbolEntry
	lda capturedSymbol+1
	sta symbolEntry+1
	jsr linkWordReference
	sec
	rts
.full:
	clc
	rts

;;; selectShortDirect / selectLongDirect
;;; Resolve the addressing-mode choice for an unresolved direct value. Explicit
;;; byte values (<label or >label) use the short mode; ordinary labels use long.
selectShortDirect:
	ldx instructionIndex
	lda directShortModes,x
	sta instructionMode
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .bad
	sta instructionOpcode
	lda #INSTRUCTION_OK
	rts
.bad:
	lda #INSTRUCTION_BAD_MODE
	rts

selectLongDirect:
	ldx instructionIndex
	lda directLongModes,x
	sta instructionMode
	tax
	lda instructionMnemonic
	jsr findOpcode
	bcc .bad
	sta instructionOpcode
	lda #INSTRUCTION_OK
	rts
.bad:
	lda #INSTRUCTION_BAD_MODE
	rts

;;; stageDeferredDirect
;;; There is no zp/absolute relaxation. A forward label is an address and uses
;;; the long form. Only an explicit < or > byte selector chooses the short form.
stageDeferredDirect:
	lda capturedPrefix
	beq .long
	jsr selectShortDirect
	cmp #INSTRUCTION_OK
	bne .bad
	jmp stageSymbolicInstruction
.long:
	jsr selectLongDirect
	cmp #INSTRUCTION_OK
	bne .bad
	jmp stageSymbolicInstruction
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts

;;; stageResolvedInstruction
;;; Emit a fully fixed non-relative instruction to staging in final byte order.
stageResolvedInstruction:
	lda instructionMode
	cmp #MODE_RELATIVE
	beq .bad
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

;;; stageResolvedRelative
;;; The target and current PC are both final, so a backward/fixed branch can be
;;; range-checked and encoded immediately.
stageResolvedRelative:
	clc
	lda assemblyPtr
	adc #$02
	sta relativeBase
	lda assemblyPtr+1
	adc #$00
	sta relativeBase+1
	sec
	lda instructionOperandValue
	sbc relativeBase
	tax
	lda instructionOperandValue+1
	sbc relativeBase+1
	cpx #$80
	bcc .positive
	cmp #$ff
	bne .range
	txa
	sta relativeByte
	jmp .stage
.positive:
	cmp #$00
	bne .range
	txa
	sta relativeByte
.stage:
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda relativeByte
	jsr stageByte
	bcc .full
	lda #ASSEMBLE_OK
	rts
.range:
	lda #ASSEMBLE_EMIT_ERROR
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; stageSymbolicInstruction
;;; Fixed-width unresolved instruction. A plain word-sized `label` uses its own
;;; two operand bytes as the forward-reference chain. Everything else gets one
;;; small exceptional fixup.
stageSymbolicInstruction:
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda stagingPtr
	sta fixupStage
	lda stagingPtr+1
	sta fixupStage+1
	ldy instructionMode
	lda modeOperandWidths,y
	cmp #$01
	beq .byte
	cmp #$02
	beq .word
	jmp .bad
.byte:
	lda #FIXUP_INSTRUCTION_BYTE
	sta fixupKind
	lda #$00
	jsr stageByte
	bcc .full
	jsr appendFixup
	bcc .full
	lda #ASSEMBLE_OK
	rts
.word:
	jsr isPlainLabelValue
	bcc .wordExpression
	jsr stagePlainWordReference
	bcc .full
	lda #ASSEMBLE_OK
	rts
.wordExpression:
	lda #FIXUP_WORD
	sta fixupKind
	lda #$00
	jsr stageByte
	bcc .full
	lda #$00
	jsr stageByte
	bcc .full
	jsr appendFixup
	bcc .full
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_INSTRUCTION
	rts
.full:
	lda #ASSEMBLE_WORK_FULL
	rts

;;; stageRelativeFixup
;;; A forward branch has fixed width but only one operand byte, so it cannot use
;;; the two-byte chain trick. Keep one small fixup until its label appears.
stageRelativeFixup:
	lda instructionOpcode
	jsr stageByte
	bcc .full
	lda stagingPtr
	sta fixupStage
	lda stagingPtr+1
	sta fixupStage+1
	lda #FIXUP_RELATIVE
	sta fixupKind
	lda #$00
	jsr stageByte
	bcc .full
	jsr appendFixup
	bcc .full
	lda #ASSEMBLE_OK
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
relativeByte:	byte 0

	include "source.asm"
	include "data.asm"
