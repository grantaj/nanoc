;;; expression_codegen.asm
;;;
;;; Direct target-code emission for expression.asm.
;;;
;;; There is deliberately no representation between the expression machine and
;;; these routines. A reduction calls the obvious emitter and ordinary `ass`
;;; source is streamed immediately. Fixed fragments below are the actual 6502
;;; sequences a reader would write by hand.

emit_load_literal:
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_string
	bcs .lowPrefix
	rts
.lowPrefix:
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcs .lowValue
	rts
.lowValue:
	jsr emit_newline
	bcs .high
	rts
.high:
	ldx #<exprLdxImm
	ldy #>exprLdxImm
	jsr emit_string
	bcs .highPrefix
	rts
.highPrefix:
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcs .done
	rts
.done:
	jmp emit_newline

emit_load_literal_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
	bcs .lowName
	rts
.lowName:
	lda currentLiteralIndex
	jsr emit_literal_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcs .highName
	rts
.highName:
	lda currentLiteralIndex
	jsr emit_literal_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_load_primary_scalar:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current

	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .persistentLowName
	rts
.persistentLowName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .persistentLowDone
	rts
.persistentLowDone:
	jsr emit_newline
	bcs .persistentWidth
	rts
.persistentWidth:
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcs .persistentHighName
	rts
.persistentHighName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .persistentHighDone
	rts
.persistentHighDone:
	jmp emit_plus_one_newline

.current:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .currentLowName
	rts
.currentLowName:
	ldx primarySymbolIndex
	jsr emit_current_name
	bcs .currentLowDone
	rts
.currentLowDone:
	jsr emit_newline
	bcs .currentWidth
	rts
.currentWidth:
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcs .currentHighName
	rts
.currentHighName:
	ldx primarySymbolIndex
	jsr emit_current_name
	bcs .currentHighDone
	rts
.currentHighDone:
	jmp emit_plus_one_newline

emit_zero_high:
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jmp emit_string

emit_load_primary_address:
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_string
	bcs .lowName
	rts
.lowName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_string
	bcs .highName
	rts
.highName:
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_plus_one_newline:
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_string
	bcs .done
	rts
.done:
	jmp emit_newline

;;; Spill storage is allocated by expression.asm. This routine merely gives the
;;; new word its deterministic assembler-visible name.
emit_spill_definition:
	sta emitSpillIndex
	jsr emit_spill_name
	bcs .assign
	rts
.assign:
	ldx #<exprBssAssign
	ldy #>exprBssAssign
	jsr emit_string
	bcs .offset
	rts
.offset:
	lda allocOffset
	sta emitWord
	lda allocOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcs .done
	rts
.done:
	jmp emit_newline

emit_store_spill:
	sta emitSpillIndex
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcs .lowName
	rts
.lowName:
	lda emitSpillIndex
	jsr emit_spill_name
	bcs .lowDone
	rts
.lowDone:
	jsr emit_newline
	bcs .high
	rts
.high:
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcs .highName
	rts
.highName:
	lda emitSpillIndex
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

;;; X=current-function symbol index; target value already lives in A/X.
emit_store_current_value:
	stx emitSavedIndex
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcs .lowName
	ldx emitSavedIndex
	rts
.lowName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .lowDone
	ldx emitSavedIndex
	rts
.lowDone:
	jsr emit_newline
	bcs .width
	ldx emitSavedIndex
	rts
.width:
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
	bcs .highName
	ldx emitSavedIndex
	rts
.highName:
	ldx emitSavedIndex
	jsr emit_current_name
	bcs .highDone
	ldx emitSavedIndex
	rts
.highDone:
	jsr emit_plus_one_newline
	bcs .done
	ldx emitSavedIndex
	rts
.done:
	ldx emitSavedIndex
	sec
	rts

emit_unary_minus:
	ldx #<exprNegate
	ldy #>exprNegate
	jmp emit_string

;;; Keep relative branches in this selector local. Every Phase 1 operator class
;;; is named explicitly; an unknown operator is an internal failure, not an
;;; accidental comparison.
emit_binary_reduction:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_MUL
	beq .mul
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
	cmp #OP_SHL
	beq .shl
	cmp #OP_SHR
	beq .shr
	cmp #OP_LT
	beq .compare
	cmp #OP_LE
	beq .compare
	cmp #OP_GT
	beq .compare
	cmp #OP_GE
	beq .compare
	cmp #OP_EQ
	beq .compare
	cmp #OP_NE
	beq .compare
	clc
	rts
.add:
	jmp emit_add_reduction
.sub:
	jmp emit_sub_reduction
.mul:
	jmp emit_mul_reduction
.and:
	jmp emit_and_reduction
.or:
	jmp emit_or_reduction
.shl:
	jmp emit_shl_reduction
.shr:
	jmp emit_shr_reduction
.compare:
	jmp emit_compare_reduction

;;; A/X is the right operand. Preserve it in the machine-contract scratch pair
;;; while the left spill is loaded.
emit_save_right_tmp:
	ldx #<exprSaveRight
	ldy #>exprSaveRight
	jmp emit_string

emit_lda_reduce_spill:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_lda_reduce_spill_high:
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_string
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

emit_add_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .addLow
	rts
.addLow:
	ldx #<exprAddLow
	ldy #>exprAddLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .addHigh
	rts
.addHigh:
	ldx #<exprAddHigh
	ldy #>exprAddHigh
	jmp emit_string

emit_sub_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .subLow
	rts
.subLow:
	ldx #<exprSubLow
	ldy #>exprSubLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .subHigh
	rts
.subHigh:
	ldx #<exprSubHigh
	ldy #>exprSubHigh
	jmp emit_string

emit_and_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .andLow
	rts
.andLow:
	ldx #<exprAndLow
	ldy #>exprAndLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .andHigh
	rts
.andHigh:
	ldx #<exprAndHigh
	ldy #>exprAndHigh
	jmp emit_string

emit_or_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .orLow
	rts
.orLow:
	ldx #<exprOrLow
	ldy #>exprOrLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .orHigh
	rts
.orHigh:
	ldx #<exprOrHigh
	ldy #>exprOrHigh
	jmp emit_string

;;; __nc_mul16 uses the frozen helper convention: left operand in NC_TMP,
;;; right operand in A/X, result in A/X. Record the helper at the exact point
;;; where a real multiplication reduction is emitted.
emit_mul_reduction:
	lda #$01
	sta multiplyUsed
	ldx #<exprMulSaveLow
	ldy #>exprMulSaveLow
	jsr emit_string
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .tail
	rts
.tail:
	ldx #<exprMulTail
	ldy #>exprMulTail
	jmp emit_string

emit_shl_reduction:
	lda #$01
	sta shiftLeftFlag
	jmp emit_shift_reduction

emit_shr_reduction:
	lda #$00
	sta shiftLeftFlag

;;; Variable shifts are deliberately a tiny generated loop. Both destinations
;;; are created within this routine, so their relative branches are local by
;;; construction; no distance analysis is required.
emit_shift_reduction:
	lda #EMIT_LABEL_GENERIC
	sta emitLabelKind
	jsr reserve_generated_label
	lda emitLabelValue
	sta shiftLoopLabel
	lda emitLabelValue+1
	sta shiftLoopLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta shiftDoneLabel
	lda emitLabelValue+1
	sta shiftDoneLabel+1

	ldx #<exprShiftCount
	ldy #>exprShiftCount
	jsr emit_string
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .saveLow
	rts
.saveLow:
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .saveHigh
	rts
.saveHigh:
	ldx #<exprStaTmpHigh
	ldy #>exprStaTmpHigh
	jsr emit_string
	bcs .zeroCheck
	rts
.zeroCheck:
	ldx #<exprCpyZero
	ldy #>exprCpyZero
	jsr emit_string
	bcs .zeroBranch
	rts
.zeroBranch:
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_string
	bcs .doneName
	rts
.doneName:
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .zeroNewline
	rts
.zeroNewline:
	jsr emit_newline
	bcs .loopLabel
	rts

.loopLabel:
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .bodyChoice
	rts
.bodyChoice:
	lda shiftLeftFlag
	beq .right
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jmp .body
.right:
	ldx #<exprShiftRightBody
	ldy #>exprShiftRightBody
.body:
	jsr emit_string
	bcs .loopBranch
	rts
.loopBranch:
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_string
	bcs .loopName
	rts
.loopName:
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .loopNewline
	rts
.loopNewline:
	jsr emit_newline
	bcs .doneLabel
	rts
.doneLabel:
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcs .result
	rts
.result:
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jmp emit_string

;;; ---------------------------------------------------------------------------
;;; Comparisons
;;; ---------------------------------------------------------------------------

;;; Statement destinations may be arbitrarily far away. For those real semantic
;;; jumps, branch over one adjacent absolute JMP so the relative branch remains
;;; local without any distance analysis.
emit_long_conditional_jump:
	stx conditionalBranchPtr
	sty conditionalBranchPtr+1
	lda emitLabelValue
	sta conditionalTargetLabel
	lda emitLabelValue+1
	sta conditionalTargetLabel+1
	lda emitLabelKind
	sta conditionalTargetKind
	jsr reserve_generated_label
	lda emitLabelValue
	sta conditionalSkipLabel
	lda emitLabelValue+1
	sta conditionalSkipLabel+1

	ldx conditionalBranchPtr
	ldy conditionalBranchPtr+1
	jsr emit_string
	bcs .skipName
	rts
.skipName:
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .branchDone
	jmp .restoreFailed
.branchDone:
	jsr emit_newline
	bcs .jump
	jmp .restoreFailed
.jump:
	lda conditionalTargetKind
	sta emitLabelKind
	lda conditionalTargetLabel
	sta emitLabelValue
	lda conditionalTargetLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcs .skipLabel
	jmp .restoreFailed
.skipLabel:
	lda #EMIT_LABEL_NEAR
	sta emitLabelKind
	lda conditionalSkipLabel
	sta emitLabelValue
	lda conditionalSkipLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	php
	lda conditionalTargetKind
	sta emitLabelKind
	plp
	rts
.restoreFailed:
	lda conditionalTargetKind
	sta emitLabelKind
	clc
	rts

;;; Comparisons are common enough in real C that spelling the complete 16-bit
;;; decision tree at every use quickly dominates the generated program. Keep the
;;; expression machine contract visible instead: right operand -> NC_TMP, reload
;;; the saved left operand into A/X, then call the small target helper matching
;;; the source operator. The helper returns the ordinary C value 0/1 in A/X.
emit_compare_reduction:
	jsr emit_save_right_tmp
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_ldx_reduce_spill_high
	bcs .call
	rts
.call:
	jmp emit_compare_helper_call

;;; A/X is already the left operand and NC_TMP is the right operand. Select the
;;; one shared 16-bit comparison helper from the source operator and the normal
;;; Phase 1 integer-conversion rule. Both spill and literal-RHS paths arrive here.
emit_compare_helper_call:
	lda #$01
	sta compareUsed
	lda reduceOperator
	cmp #OP_EQ
	beq .equal
	cmp #OP_NE
	beq .notEqual
	jsr combined_integer_type
	cmp #TYPE_UNSIGNED
	beq .unsigned

	lda reduceOperator
	cmp #OP_LT
	beq .signedLt
	cmp #OP_LE
	beq .signedLe
	cmp #OP_GT
	beq .signedGt
	ldx #<exprCallSge16
	ldy #>exprCallSge16
	jmp emit_compare_call
.signedLt:
	ldx #<exprCallSlt16
	ldy #>exprCallSlt16
	jmp emit_compare_call
.signedLe:
	ldx #<exprCallSle16
	ldy #>exprCallSle16
	jmp emit_compare_call
.signedGt:
	ldx #<exprCallSgt16
	ldy #>exprCallSgt16
	jmp emit_compare_call

.unsigned:
	lda reduceOperator
	cmp #OP_LT
	beq .unsignedLt
	cmp #OP_LE
	beq .unsignedLe
	cmp #OP_GT
	beq .unsignedGt
	ldx #<exprCallUge16
	ldy #>exprCallUge16
	jmp emit_compare_call
.unsignedLt:
	ldx #<exprCallUlt16
	ldy #>exprCallUlt16
	jmp emit_compare_call
.unsignedLe:
	ldx #<exprCallUle16
	ldy #>exprCallUle16
	jmp emit_compare_call
.unsignedGt:
	ldx #<exprCallUgt16
	ldy #>exprCallUgt16
	jmp emit_compare_call

.equal:
	ldx #<exprCallEq16
	ldy #>exprCallEq16
	jmp emit_compare_call
.notEqual:
	ldx #<exprCallNe16
	ldy #>exprCallNe16
	jmp emit_compare_call

emit_compare_call:
	jsr emit_string
	bcs .done
	rts
.done:
	jmp emit_newline

emit_ldx_reduce_spill_high:
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_string
	bcs .name
	rts
.name:
	lda reduceSpill
	jsr emit_spill_name
	bcs .done
	rts
.done:
	jmp emit_plus_one_newline

emit_jump_label:
	ldx #<exprJmp
	ldy #>exprJmp
	jsr emit_string
	bcs .name
	rts
.name:
	jsr emit_generated_label_name
	bcs .done
	rts
.done:
	jmp emit_newline

emit_label_definition:
	jsr emit_generated_label_name
	bcs .colon
	rts
.colon:
	lda #':'
	jsr emit_output_byte
	bcs .done
	rts
.done:
	jmp emit_newline

;;; Index value is in target A/X. reduceSpill is the saved full 16-bit base.
;;; Non-char global arrays scale the index by two before address addition.
;;; This routine ends with the effective address in NC_PTR and emits no load.
;;; Indexed reads call it and then load; indexed assignments reuse it directly.
emit_index_address:
	jsr emit_save_right_tmp
	bcs .scale
	rts
.scale:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .leftLow
	ldx #<exprScaleIndex
	ldy #>exprScaleIndex
	jsr emit_string
	bcs .leftLow
	rts
.leftLow:
	jsr emit_lda_reduce_spill
	bcs .addressLow
	rts
.addressLow:
	ldx #<exprIndexLow
	ldy #>exprIndexLow
	jsr emit_string
	bcs .leftHigh
	rts
.leftHigh:
	jsr emit_lda_reduce_spill_high
	bcs .addressHigh
	rts
.addressHigh:
	ldx #<exprIndexHigh
	ldy #>exprIndexHigh
	jmp emit_string

emit_index_load:
	jsr emit_index_address
	bcs .load
	rts
.load:
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .char
	ldx #<exprWordIndirect
	ldy #>exprWordIndirect
	jmp emit_string
.char:
	ldx #<exprCharIndirect
	ldy #>exprCharIndirect
	jmp emit_string

;;; ---------------------------------------------------------------------------
;;; Fixed target-source fragments
;;; ---------------------------------------------------------------------------
;;;
;;; The End labels are retained temporarily because a few focused test/formatter
;;; callers still use the old explicit-length seam. Each End points before the
;;; NUL, so those callers see exactly the same bytes while production uses
;;; emit_string.

exprLdaImm:		byte $09,'l','d','a',' ','#','$'
exprLdaImmEnd:		byte 0
exprLdxImm:		byte $09,'l','d','x',' ','#','$'
exprLdxImmEnd:		byte 0
exprLdaLowImm:		byte $09,'l','d','a',' ','#','<'
exprLdaLowImmEnd:	byte 0
exprLdxHighImm:		byte $09,'l','d','x',' ','#','>'
exprLdxHighImmEnd:	byte 0
exprLdaSpace:		byte $09,'l','d','a',' '
exprLdaSpaceEnd:		byte 0
exprLdxSpace:		byte $09,'l','d','x',' '
exprLdxSpaceEnd:		byte 0
exprStaSpace:		byte $09,'s','t','a',' '
exprStaSpaceEnd:		byte 0
exprStxSpace:		byte $09,'s','t','x',' '
exprStxSpaceEnd:		byte 0
exprLdxZero:		byte $09,'l','d','x',' ','#','$','0','0',$0a
exprLdxZeroEnd:		byte 0
exprPlusOne:		byte '+','1'
exprPlusOneEnd:		byte 0
exprBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
exprBssAssignEnd:	byte 0
exprBytePrefix:		byte $09,'b','y','t','e',' '
exprBytePrefixEnd:	byte 0

exprNegate:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprNegateEnd:		byte 0

exprSaveRight:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
exprSaveRightEnd:	byte 0
exprAddLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAddLowEnd:		byte 0
exprAddHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAddHighEnd:		byte 0
exprSubLow:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprSubLowEnd:		byte 0
exprSubHigh:
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprSubHighEnd:		byte 0
exprAndLow:
	byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAndLowEnd:		byte 0
exprAndHigh:
	byte $09,'a','n','d',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAndHighEnd:		byte 0
exprOrLow:
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprOrLowEnd:		byte 0
exprOrHigh:
	byte $09,'o','r','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprOrHighEnd:		byte 0

exprMulSaveLow:		byte $09,'t','a','y',$0a
exprMulSaveLowEnd:	byte 0
exprStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
exprStaTmpEnd:		byte 0
exprStaTmpHigh:		byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
exprStaTmpHighEnd:	byte 0
exprMulTail:
	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','y','a',$0a
	byte $09,'j','s','r',' ','_','_','n','c','_','m','u','l','1','6',$0a
exprMulTailEnd:		byte 0

exprShiftCount:		byte $09,'t','a','y',$0a
exprShiftCountEnd:	byte 0
exprCpyZero:		byte $09,'c','p','y',' ','#','$','0','0',$0a
exprCpyZeroEnd:		byte 0
exprShiftLeftBody:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'d','e','y',$0a
exprShiftLeftBodyEnd:	byte 0
exprShiftRightBody:
	byte $09,'l','s','r',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','T','M','P',$0a
	byte $09,'d','e','y',$0a
exprShiftRightBodyEnd:	byte 0
exprLoadTmpResult:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','x',' ','N','C','_','T','M','P','+','1',$0a
exprLoadTmpResultEnd:	byte 0

exprBne:		byte $09,'b','n','e',' '
exprBneEnd:		byte 0
exprBeq:		byte $09,'b','e','q',' '
exprBeqEnd:		byte 0
exprJmp:		byte $09,'j','m','p',' '
exprJmpEnd:		byte 0
exprCallEq16:		byte $09
			string "jsr __nc_eq16"
exprCallNe16:		byte $09
			string "jsr __nc_ne16"
exprCallSlt16:		byte $09
			string "jsr __nc_slt16"
exprCallSle16:		byte $09
			string "jsr __nc_sle16"
exprCallSgt16:		byte $09
			string "jsr __nc_sgt16"
exprCallSge16:		byte $09
			string "jsr __nc_sge16"
exprCallUlt16:		byte $09
			string "jsr __nc_ult16"
exprCallUle16:		byte $09
			string "jsr __nc_ule16"
exprCallUgt16:		byte $09
			string "jsr __nc_ugt16"
exprCallUge16:		byte $09
			string "jsr __nc_uge16"

exprScaleIndex:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
exprScaleIndexEnd:	byte 0
exprIndexLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
exprIndexLowEnd:	byte 0
exprIndexHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R','+','1',$0a
exprIndexHighEnd:	byte 0
exprCharIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprCharIndirectEnd:	byte 0
exprWordIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'t','a','x',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
exprWordIndirectEnd:	byte 0

;;; Scratch used only while formatting a branch-over-JMP statement transfer.
conditionalBranchPtr:		word 0
conditionalTargetLabel:	word 0
conditionalSkipLabel:		word 0
conditionalTargetKind:	byte EMIT_LABEL_GENERIC
