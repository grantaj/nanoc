;;; statement_codegen.asm
;;;
;;; Direct target-code emission for statements.asm.
;;;
;;; This file is deliberately only spelling: the statement parser decides what
;;; source construct it has and calls the obvious emitter immediately. There is
;;; no statement representation between the two files.

;;; The statement target is already a named array or pointer. Save the index in
;;; NC_TMP, scale it when required, load the named base into A/X, then call the
;;; same tiny 16-bit address helper used by expression reads.
emit_statement_index_address:
	lda statementElementType
	sta reduceLeftType
	jsr emit_index_offset
	bcc .failed
	jsr load_statement_target_base
	bcc .failed
	jmp emit_index_address_call
.failed:
	clc
	rts

load_statement_target_base:
	lda statementTargetIndex
	sta primarySymbolIndex
	lda statementTargetArea
	sta primarySymbolArea
	lda statementTargetKind
	sta primarySymbolKind
	lda statementTargetType
	sta primarySymbolType
	lda statementTargetKind
	cmp #SYMBOL_ARRAY
	beq .array
	jmp emit_load_primary_scalar_now
.array:
	jmp emit_load_primary_address

;;; Exact byte `x = x +/- 1` updates the named object in place. Word values
;;; stay on the ordinary immediate arithmetic path, which already carries or
;;; borrows explicitly across A/X.
emit_direct_scalar_update:
	lda pendingOperator
	cmp #OP_SUB
	beq .subtract
	ldx #<statementIncSpace
	ldy #>statementIncSpace
	jmp emit_primary_scalar_line
.subtract:
	ldx #<statementDecSpace
	ldy #>statementDecSpace
	jmp emit_primary_scalar_line

;;; Phase 1 C functions return int. A byte or lazy comparison therefore becomes
;;; a complete A/X value only here, at the observable call boundary.
emit_return_value:
	jsr ensure_expression_word
	bcc .failed
	ldx #<statementRts
	ldy #>statementRts
	jmp emit_string
.failed:
	clc
	rts

emit_store_persistent_value:
	lda statementTargetType
	cmp #TYPE_CHAR
	bne .word
	jsr ensure_expression_byte_value
	bcc .failed
	jmp .low
.word:
	jsr ensure_expression_word
	bcc .failed
.low:
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcc .failed
	ldx statementTargetIndex
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda statementTargetType
	cmp #TYPE_CHAR
	beq .done
	lda #exprStxSpaceEnd-exprStxSpace
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_text
	bcc .failed
	ldx statementTargetIndex
	jsr emit_persistent_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

emit_statement_address_name:
	ldx #<emitCPrefix
	ldy #>emitCPrefix
	jsr emit_string
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	ldx #<statementAddressSuffix
	ldy #>statementAddressSuffix
	jmp emit_string
.failed:
	clc
	rts

emit_statement_address_definition:
	jsr emit_statement_address_name
	bcc .failed
	lda #exprBssAssignEnd-exprBssAssign
	ldx #<exprBssAssign
	ldy #>exprBssAssign
	jsr emit_text
	bcc .failed
	lda allocOffset
	sta emitWord
	lda allocOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; X/Y names an instruction prefix such as "sta " or "ldx ". Spell that
;;; instruction with the current function's one reusable indexed-lvalue slot.
emit_statement_address_low:
	jsr emit_string
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_statement_address_high:
	jsr emit_string
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jmp emit_plus_one_newline
.failed:
	clc
	rts

;;; A direct byte-index lvalue needs only the low index byte across its RHS.
emit_save_statement_index:
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jmp emit_statement_address_low

emit_save_statement_address:
	lda #EMIT_TRANSIENT_SPILL
	sta reduceSpill
	jsr emit_lda_reduce_spill
	bcc .failed
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_statement_address_low
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jmp emit_statement_address_high
.failed:
	clc
	rts

;;; Direct char[] stores keep only the byte index and use absolute,Y. A current
;;; char * reloads its named pointer into NC_PTR and uses the saved byte as Y.
;;; Every other case retains the saved full-address fallback below.
emit_indexed_store:
	lda statementTargetKind
	cmp #STATEMENT_INDEX_ARRAY
	beq emit_indexed_array_store
	cmp #STATEMENT_INDEX_CURRENT_PTR
	beq emit_indexed_current_pointer_store

	;;; The RHS value and the saved lvalue address have independent widths. A char
	;;; store needs only A across the address restore; a word store keeps A/X.
	lda statementElementType
	cmp #TYPE_CHAR
	bne .saveWord
	jsr emit_save_right_byte_tmp
	jmp .saved
.saveWord:
	jsr emit_save_right_tmp
.saved:
	bcc .failed
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_statement_address_low
	bcc .failed
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_statement_address_high
	bcc .failed
	jsr emit_store_transient
	bcc .failed

	lda statementElementType
	cmp #TYPE_CHAR
	beq .char
	ldx #<statementStoreWord
	ldy #>statementStoreWord
	jmp emit_string
.char:
	ldx #<statementStoreChar
	ldy #>statementStoreChar
	jmp emit_string
.failed:
	clc
	rts

emit_indexed_array_store:
	jsr ensure_expression_byte_value
	bcc .failed
	ldx #<statementLdySpace
	ldy #>statementLdySpace
	jsr emit_statement_address_low
	bcc .failed
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcc .failed
	ldx statementTargetIndex
	jsr emit_persistent_name
	bcc .failed
	ldx #<exprIndexYSuffix
	ldy #>exprIndexYSuffix
	jmp emit_string
.failed:
	clc
	rts

emit_indexed_current_pointer_store:
	jsr emit_save_right_byte_tmp
	bcc .failed
	jsr load_statement_target_base
	bcc .failed
	jsr emit_store_transient
	bcc .failed
	ldx #<statementLdySpace
	ldy #>statementLdySpace
	jsr emit_statement_address_low
	bcc .failed
	ldx #<statementStoreCharY
	ldy #>statementStoreCharY
	jmp emit_string
.failed:
	clc
	rts

;;; Use a live comparison/value flag when one is available. Otherwise form truth
;;; from the physical value width: a byte needs one CMP, while a genuine word
;;; collapses high/low. The selected branch always means target "true" and skips
;;; the adjacent arbitrary-distance false JMP.
emit_statement_false_jump:
	lda expressionConditionBranch
	beq .formTruth
	cmp #EXPR_CONDITION_BNE
	beq .bne
	cmp #EXPR_CONDITION_BEQ
	beq .beq
	cmp #EXPR_CONDITION_BCC
	beq .bcc
	cmp #EXPR_CONDITION_BCS
	beq .bcs
	clc
	rts

.formTruth:
	lda expressionPhysicalKind
	cmp #EXPR_VALUE_BYTE
	beq .byte
	cmp #EXPR_VALUE_WORD
	beq .word
	clc
	rts
.byte:
	ldx #<statementByteTruthTest
	ldy #>statementByteTruthTest
	jsr emit_string
	bcc .failed
	jmp .bne
.word:
	ldx #<statementTruthTest
	ldy #>statementTruthTest
	jsr emit_string
	bcc .failed
.bne:
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump
.beq:
	ldx #<exprBeq
	ldy #>exprBeq
	jmp emit_long_conditional_jump
.bcc:
	ldx #<exprBcc
	ldy #>exprBcc
	jmp emit_long_conditional_jump
.bcs:
	ldx #<exprBcs
	ldy #>exprBcs
	jmp emit_long_conditional_jump
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed emitted fragments
;;; ---------------------------------------------------------------------------

statementRts:		byte $09,'r','t','s',$0a,0
statementAddressSuffix:	byte '_','_','a',0
statementLdySpace:	byte $09,'l','d','y',' ',0
statementIncSpace:	byte $09,'i','n','c',' ',0
statementDecSpace:	byte $09,'d','e','c',' ',0
statementByteTruthTest:
	byte $09,'c','m','p',' ','#','$','0','0',$0a,0
statementTruthTest:
	byte $09,'s','t','x',' ','N','C','_','T','M','P',$0a
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a,0
statementStoreChar:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
statementStoreCharY:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a,0
statementStoreWord:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a,0
