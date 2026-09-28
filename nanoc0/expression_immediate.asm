;;; expression_immediate.asm
;;;
;;; Concrete operand handling for the direct expression machine.
;;;
;;; These routines know only the small physical forms a 6502 instruction can
;;; consume directly: immediate literals, named scalar memory, fixed addresses,
;;; A, A/X, live byte-comparison flags, and a short value on the hardware stack.
;;; There is no generic value object or register allocator here.

;;; ---------------------------------------------------------------------------
;;; Result-state helpers
;;; ---------------------------------------------------------------------------

mark_expression_a:
	lda #VALUE_A
	sta expressionValueKind
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	sec
	rts

mark_expression_a_truth:
	lda #VALUE_A
	sta expressionValueKind
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	sec
	rts

mark_expression_ax:
	lda #VALUE_AX
	sta expressionValueKind
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	sec
	rts

mark_expression_ax_truth:
	lda #VALUE_AX
	sta expressionValueKind
	lda #EXPR_CONDITION_BNE
	sta expressionConditionBranch
	sec
	rts

mark_expression_condition:
	;;; A is one VALUE_COND_* kind describing the live CMP flags.
	sta expressionValueKind
	lda #EXPR_CONDITION_NONE
	sta expressionConditionBranch
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; One straight-line scalar owner (#98)
;;; ---------------------------------------------------------------------------

;;; The generated machine may carry one named scalar in A or A/X while its static
;;; backing slot is stale. This is intentionally smaller than a register model:
;;; no liveness set, no allocation, and no merge state. Any ambiguous boundary
;;; spills or forgets this single fact.
resident_expression_matches:
	lda residentArea
	beq .no
	lda expressionValueKind
	cmp #VALUE_CURRENT
	beq .current
	cmp #VALUE_PERSISTENT
	bne .no
	lda residentArea
	cmp #SYMBOL_AREA_PERSISTENT
	bne .no
	jmp .identity
.current:
	lda residentArea
	cmp #SYMBOL_AREA_CURRENT
	bne .no
.identity:
	lda expressionValueLow
	cmp residentIndex
	bne .no
	lda expressionValueType
	cmp residentType
	bne .no
	sec
	rts
.no:
	clc
	rts

emit_resident_name:
	ldx residentIndex
	lda residentArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	cmp #SYMBOL_AREA_PERSISTENT
	bne .failed
	jmp emit_persistent_name
.current:
	jmp emit_current_name
.failed:
	clc
	rts

;;; Commit a stale owner before generated code reuses A/X or crosses a boundary.
;;; STA/STX preserve 6502 condition flags, which lets this routine sit between a
;;; CMP and its branch without manufacturing a Boolean.
resident_spill_and_forget:
	lda residentArea
	beq .done
	lda residentDirty
	beq .forget
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcc .failed
	jsr emit_resident_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda residentType
	cmp #TYPE_CHAR
	beq .forget
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcc .failed
	jsr emit_resident_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
.forget:
	lda #$00
	sta residentArea
	sta residentDirty
.done:
	sec
	rts
.failed:
	clc
	rts

resident_forget:
	lda #$00
	sta residentArea
	sta residentDirty
	sec
	rts

;;; The final C-defined argument already arrives in its natural return registers.
;;; Parameters are the first current-function symbols, so count-1 identifies the
;;; one value whose backing slot has not yet been written.
resident_begin_function_parameter:
	jsr resident_forget
	ldx currentFunctionIndex
	lda persistentParamCount,x
	beq .done
	sec
	sbc #$01
	sta residentIndex
	tax
	lda currentType,x
	sta residentType
	lda #SYMBOL_AREA_CURRENT
	sta residentArea
	lda #$01
	sta residentDirty
.done:
	sec
	rts

;;; Locals/parameters have no externally visible backing-store requirement at
;;; function exit. A dirty global does, so commit only that case.
resident_finish_function:
	lda residentArea
	cmp #SYMBOL_AREA_PERSISTENT
	beq resident_spill_and_forget
	jmp resident_forget

;;; A completed scalar assignment rebinds the one machine owner to its target.
;;; Any different old owner is committed first; stores do not disturb the new
;;; A/A-X value being assigned.
resident_bind_statement_target:
	jsr resident_spill_and_forget
	bcc .failed
	lda statementTargetArea
	sta residentArea
	lda statementTargetIndex
	sta residentIndex
	lda statementTargetType
	sta residentType
	lda #$01
	sta residentDirty
	sec
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Operand names
;;; ---------------------------------------------------------------------------

emit_expression_scalar_name:
	ldx expressionValueLow
	lda expressionValueKind
	cmp #VALUE_CURRENT
	beq .current
	cmp #VALUE_PERSISTENT
	bne .failed
	jmp emit_persistent_name
.current:
	jmp emit_current_name
.failed:
	clc
	rts

emit_right_scalar_name:
	ldx reduceRightLow
	lda reduceRightKind
	cmp #VALUE_CURRENT
	beq .current
	cmp #VALUE_PERSISTENT
	bne .failed
	jmp emit_persistent_name
.current:
	jmp emit_current_name
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Materialise the current operand only when a consumer asks for registers
;;; ---------------------------------------------------------------------------

materialize_expression_byte:
	jsr resident_expression_matches
	bcc .ordinary
	jmp mark_expression_a
.ordinary:
	lda expressionValueKind
	cmp #VALUE_A
	bne .notReadyByte
	jmp .ready
.notReadyByte:
	cmp #VALUE_AX
	beq .narrow
	cmp #VALUE_LITERAL
	beq .literal
	cmp #VALUE_CURRENT
	beq .scalar
	cmp #VALUE_PERSISTENT
	beq .scalar
	cmp #VALUE_STACK_BYTE
	beq .stackByte
	cmp #VALUE_STACK_WORD
	beq .stackWord
	cmp #VALUE_COND_EQ
	bcc .failed
	cmp #VALUE_COND_LE+1
	bcs .failed
	jmp materialize_expression_condition

.narrow:
	jmp mark_expression_a
.literal:
	jsr resident_spill_and_forget
	bcc .middleFailed
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_string
	bcc .failed
	lda expressionValueLow
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	jmp mark_expression_a_truth
.scalar:
	jsr resident_spill_and_forget
	bcc .middleFailed
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcc .middleFailed
	jsr emit_expression_scalar_name
	bcc .middleFailed
	jsr emit_newline
	bcc .middleFailed
	jmp mark_expression_a_truth
.stackByte:
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprPla
	ldy #>exprPla
	jsr emit_string
	bcc .failed
	jmp mark_expression_a_truth
.stackWord:
	;;; Word pushes place high on top. Discard it, then recover the low byte.
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprPlaPla
	ldy #>exprPlaPla
	jsr emit_string
	bcc .failed
	jmp mark_expression_a_truth
.ready:
	sec
	rts
.failed:
	clc
	rts

materialize_expression_word:
	jsr resident_expression_matches
	bcc .ordinary
	lda expressionValueType
	cmp #TYPE_CHAR
	beq .residentByte
	jmp mark_expression_ax
.residentByte:
	;;; A already owns the byte; only a genuine word consumer needs X=0.
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jsr emit_string
	bcc .upperFailed
	jmp mark_expression_ax
.ordinary:
	lda expressionValueKind
	cmp #VALUE_AX
	bne .notAx
	jmp .ready
.notAx:
	cmp #VALUE_A
	bne .notA
	jmp .extend
.notA:
	cmp #VALUE_LITERAL
	bne .notLiteral
	jmp .literal
.notLiteral:
	cmp #VALUE_CURRENT
	beq .scalarJump
	cmp #VALUE_PERSISTENT
	bne .notScalar
.scalarJump:
	jmp .scalar
.notScalar:
	cmp #VALUE_STRING
	bne .notString
	jmp .string
.notString:
	cmp #VALUE_ARRAY
	bne .notArray
	jmp .array
.notArray:
	cmp #VALUE_STACK_BYTE
	bne .notStackByte
	jmp .stackByte
.notStackByte:
	cmp #VALUE_STACK_WORD
	bne .notStackWord
	jmp .stackWord
.notStackWord:
	cmp #VALUE_COND_EQ
	bcs .conditionRange
	jmp .failed
.conditionRange:
	cmp #VALUE_COND_LE+1
	bcc .condition
	jmp .failed
.condition:
	jsr materialize_expression_condition
	bcs .conditionDone
	jmp .failed
.conditionDone:
	jmp .extend
.upperFailed:
	clc
	rts

.extend:
	jsr resident_spill_and_forget
	bcc .middleFailed
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jsr emit_string
	bcs .extended
	rts
.extended:
	jmp mark_expression_ax

.literal:
	jsr resident_spill_and_forget
	bcc .failed
	jsr emit_load_literal
	bcs .literalDone
	rts
.literalDone:
	jmp mark_expression_ax

.scalar:
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcc .failed
	jsr emit_expression_scalar_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda expressionValueType
	cmp #TYPE_CHAR
	beq .extend
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcc .middleFailed
	jsr emit_expression_scalar_name
	bcc .middleFailed
	jsr emit_plus_one_newline
	bcc .middleFailed
	jmp mark_expression_ax
.middleFailed:
	clc
	rts

.string:
	jsr resident_spill_and_forget
	bcc .failed
	jsr emit_load_literal_address
	bcc .failed
	jmp mark_expression_ax

.array:
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
	bcc .failed
	ldx expressionValueLow
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcc .failed
	ldx expressionValueLow
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	jmp mark_expression_ax

.stackByte:
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprPla
	ldy #>exprPla
	jsr emit_string
	bcc .failed
	jmp .extend
.stackWord:
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprPopWord
	ldy #>exprPopWord
	jsr emit_string
	bcc .failed
	jmp mark_expression_ax
.ready:
	sec
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Consume an operator-stack left operand
;;; ---------------------------------------------------------------------------

select_saved_operand:
	;;; reduceRight* already owns the RHS at reduction time, so the old current
	;;; descriptor is dead once a saved left operand is selected for emission.
	lda reduceLeftKind
	sta expressionValueKind
	lda reduceLeftLow
	sta expressionValueLow
	lda reduceLeftHigh
	sta expressionValueHigh
	lda reduceLeftType
	sta expressionValueType
	rts

materialize_saved_byte:
	jsr select_saved_operand
	jmp materialize_expression_byte

materialize_saved_word:
	jsr select_saved_operand
	jmp materialize_expression_word

;;; An index marker stores the element type in operatorType because that becomes
;;; the expression result. Its saved operand is nevertheless an address: a named
;;; scalar base is a char *, while VALUE_ARRAY/STACK_WORD do not consult this type.
materialize_saved_address:
	jsr select_saved_operand
	lda #TYPE_CHAR_PTR
	sta expressionValueType
	jmp materialize_expression_word

;;; ---------------------------------------------------------------------------
;;; Short hardware-stack lifetimes
;;; ---------------------------------------------------------------------------

emit_push_saved_operand:
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .word
	jsr materialize_saved_byte
	bcc .failed
	ldx #<exprPha
	ldy #>exprPha
	jmp emit_string
.word:
	jsr materialize_saved_word
	bcc .failed
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprPushWord
	ldy #>exprPushWord
	jmp emit_string
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Direct right-hand operands for ADC/SBC/AND/ORA/CMP
;;; ---------------------------------------------------------------------------

right_operand_is_direct:
	lda reduceRightKind
	cmp #VALUE_LITERAL
	beq .yes
	cmp #VALUE_CURRENT
	beq .yes
	cmp #VALUE_PERSISTENT
	beq .yes
	clc
	rts
.yes:
	sec
	rts

;;; X/Y points at a mnemonic prefix ending in a space. Emit its low-byte operand.
emit_right_low_operand:
	stx operandPrefix
	sty operandPrefix+1
	lda reduceRightKind
	cmp #VALUE_LITERAL
	beq .literal
	cmp #VALUE_CURRENT
	beq .scalar
	cmp #VALUE_PERSISTENT
	beq .scalar
	clc
	rts
.literal:
	ldx operandPrefix
	ldy operandPrefix+1
	jsr emit_string
	bcc .failed
	ldx #<exprImmediateMarker
	ldy #>exprImmediateMarker
	jsr emit_string
	bcc .failed
	lda reduceRightLow
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.scalar:
	;;; A direct memory RHS must not name a stale backing slot. If a resident
	;;; owner is live here it is the value still in A/X, so committing it is safe.
	jsr resident_spill_and_forget
	bcc .failed
	ldx operandPrefix
	ldy operandPrefix+1
	jsr emit_string
	bcc .failed
	jsr emit_right_scalar_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; X/Y points at the same mnemonic prefix. Emit the promoted high byte.
emit_right_high_operand:
	stx operandPrefix
	sty operandPrefix+1
	lda reduceRightKind
	cmp #VALUE_LITERAL
	beq .literal
	cmp #VALUE_CURRENT
	beq .scalar
	cmp #VALUE_PERSISTENT
	beq .scalar
	clc
	rts
.literal:
	ldx operandPrefix
	ldy operandPrefix+1
	jsr emit_string
	bcc .failed
	ldx #<exprImmediateMarker
	ldy #>exprImmediateMarker
	jsr emit_string
	bcc .failed
	lda reduceRightHigh
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.scalar:
	lda reduceRightType
	cmp #TYPE_CHAR
	beq .zero
	ldx operandPrefix
	ldy operandPrefix+1
	jsr emit_string
	bcc .failed
	jsr emit_right_scalar_name
	bcc .failed
	jmp emit_plus_one_newline
.zero:
	ldx operandPrefix
	ldy operandPrefix+1
	jsr emit_string
	bcc .failed
	ldx #<exprImmediateZero
	ldy #>exprImmediateZero
	jmp emit_string
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Cheap domain facts used only to choose exact byte instructions
;;; ---------------------------------------------------------------------------

left_operand_is_byte_domain:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .yes
	lda reduceLeftKind
	cmp #VALUE_STACK_BYTE
	beq .yes
	cmp #VALUE_LITERAL
	bne .no
	lda reduceLeftHigh
	beq .yes
.no:
	clc
	rts
.yes:
	sec
	rts

right_operand_is_byte_domain:
	lda reduceRightType
	cmp #TYPE_CHAR
	beq .yes
	lda reduceRightKind
	cmp #VALUE_LITERAL
	bne .condition
	lda reduceRightHigh
	beq .yes
.condition:
	lda reduceRightKind
	cmp #VALUE_COND_EQ
	bcc .no
	cmp #VALUE_COND_LE+1
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

;;; A reduction narrows only when its actual delimiter proves that the high byte
;;; cannot be observed. Statement-owned expressions publish their destination type
;;; before parsing. Call arguments use the active call frame; a grouping ')' is
;;; rejected by call_delimiter_belongs_to_call and therefore cannot leak a byte
;;; promise into an inner expression.
final_consumer_observes_byte:
	lda currentTokenKind
	cmp #';'
	beq .statement
	cmp #','
	beq .call
	cmp #')'
	bne .no
.call:
	jsr call_delimiter_belongs_to_call
	bcc .no
	jsr current_call_parameter_type
	bcc .no
	cmp #TYPE_CHAR
	beq .yes
	clc
	rts
.statement:
	lda statementConsumerType
	cmp #TYPE_CHAR
	bne .no
.yes:
	sec
	rts
.no:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Materialise a live byte comparison only when C actually observes 0/1
;;; ---------------------------------------------------------------------------

;;; PHP/PLA exposes the CMP flags as ordinary bits. This is cheaper and clearer
;;; than manufacturing labels just to obtain 0/1: Z is bit 1, C is bit 0, and
;;; GT is C & !Z. __nc_init keeps decimal mode clear, so ADC #$00 is ordinary
;;; binary addition in the GT/LE combiner.
materialize_expression_condition:
	;;; The following PHP/PLA overwrites A. Commit a resident scalar first; the
	;;; emitted STA/STX instructions leave the comparison flags untouched.
	jsr resident_spill_and_forget
	bcc .failed
	ldx #<exprStatusToA
	ldy #>exprStatusToA
	jsr emit_string
	bcc .failed
	lda expressionValueKind
	cmp #VALUE_COND_EQ
	beq .equality
	cmp #VALUE_COND_NE
	beq .equalityInvert
	cmp #VALUE_COND_LT
	beq .carryInvert
	cmp #VALUE_COND_GE
	beq .carry
	cmp #VALUE_COND_GT
	beq .greater
	cmp #VALUE_COND_LE
	bne .failed
	jsr emit_greater_condition_bits
	bcc .failed
	jmp .invert
.equalityInvert:
	jsr emit_equality_condition_bits
	bcc .failed
	jmp .invert
.equality:
	jsr emit_equality_condition_bits
	bcc .failed
	jmp mark_expression_a_truth
.carryInvert:
	jsr emit_carry_condition_bit
	bcc .failed
	jmp .invert
.carry:
	jsr emit_carry_condition_bit
	bcc .failed
	jmp mark_expression_a_truth
.greater:
	jsr emit_greater_condition_bits
	bcc .failed
	jmp mark_expression_a_truth
.invert:
	ldx #<exprInvertBit
	ldy #>exprInvertBit
	jsr emit_string
	bcc .failed
	jmp mark_expression_a_truth
.failed:
	clc
	rts

emit_equality_condition_bits:
	ldx #<exprEqualityBit
	ldy #>exprEqualityBit
	jmp emit_string

emit_carry_condition_bit:
	ldx #<exprCarryBit
	ldy #>exprCarryBit
	jmp emit_string

emit_greater_condition_bits:
	ldx #<exprGreaterBit
	ldy #>exprGreaterBit
	jmp emit_string

;;; ---------------------------------------------------------------------------
;;; Fixed fragments used by the operand seam
;;; ---------------------------------------------------------------------------

exprImmediateMarker:	byte '#','$',0
exprImmediateZero:	byte '#','$','0','0',$0a,0
exprStatusToA:
	byte $09,'p','h','p',$0a
	byte $09,'p','l','a',$0a,0
exprEqualityBit:
	byte $09,'a','n','d',' ','#','$','0','2',$0a
	byte $09,'l','s','r',$0a,0
exprCarryBit:
	byte $09,'a','n','d',' ','#','$','0','1',$0a,0
exprGreaterBit:
	byte $09,'a','n','d',' ','#','$','0','3',$0a
	byte $09,'l','s','r',$0a
	byte $09,'e','o','r',' ','#','$','0','1',$0a
	byte $09,'a','d','c',' ','#','$','0','0',$0a
	byte $09,'l','s','r',$0a,0
exprInvertBit:
	byte $09,'e','o','r',' ','#','$','0','1',$0a,0
exprPha:		byte $09,'p','h','a',$0a,0
exprPla:		byte $09,'p','l','a',$0a,0
exprPushWord:
	byte $09,'p','h','a',$0a
	byte $09,'t','x','a',$0a
	byte $09,'p','h','a',$0a,0
exprPopWord:
	byte $09,'p','l','a',$0a
	byte $09,'t','a','x',$0a
	byte $09,'p','l','a',$0a,0
exprPlaPla:
	byte $09,'p','l','a',$0a
	byte $09,'p','l','a',$0a,0
