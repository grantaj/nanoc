;;; statement_codegen.asm
;;;
;;; Direct target-code emission for statements.asm.
;;;
;;; This file is deliberately only spelling: the statement parser decides what
;;; source construct it has and calls the obvious emitter immediately. There is
;;; no statement representation between the two files.

;;; Index is in target A/X on entry. The normal expression spill stack is idle
;;; because parse_expression has completed, so one spill may temporarily hold
;;; the lvalue base. #55's emit_index_address then performs the one authoritative
;;; scale-and-add operation and leaves the complete effective address in NC_PTR.
emit_statement_index_address:
	jsr emit_save_right_tmp
	bcc .emitFailed
	jsr load_statement_target_base
	bcc .emitFailed
	jsr spill_current_value
	bcs .baseSpilled
	clc
	rts
.baseSpilled:
	lda expressionSpillDepth
	sec
	sbc #$01
	sta reduceSpill
	lda statementElementType
	sta reduceLeftType

	;;; Loading the named base above replaced A/X, so restore the already-evaluated
	;;; index before entering the shared address emitter.
	lda #exprLoadTmpResultEnd-exprLoadTmpResult
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jsr emit_text
	bcc .releaseFailed
	jsr emit_index_address
	php
	dec expressionSpillDepth
	plp
	rts
.releaseFailed:
	dec expressionSpillDepth
.emitFailed:
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
	jmp emit_load_primary_scalar
.array:
	jmp emit_load_primary_address

emit_return_value:
	lda #statementRtsEnd-statementRts
	ldx #<statementRts
	ldy #>statementRts
	jmp emit_text

emit_store_persistent_value:
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
	lda #emitCPrefixEnd-emitCPrefix
	ldx #<emitCPrefix
	ldy #>emitCPrefix
	jsr emit_text
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	lda #statementAddressSuffixEnd-statementAddressSuffix
	ldx #<statementAddressSuffix
	ldy #>statementAddressSuffix
	jmp emit_text
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

emit_save_statement_address:
	lda #statementLdaPtrEnd-statementLdaPtr
	ldx #<statementLdaPtr
	ldy #>statementLdaPtr
	jsr emit_text
	bcc .failed
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #statementLdaPtrHighEnd-statementLdaPtrHigh
	ldx #<statementLdaPtrHigh
	ldy #>statementLdaPtrHigh
	jsr emit_text
	bcc .failed
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jmp emit_plus_one_newline
.failed:
	clc
	rts

;;; RHS A/X is saved in NC_TMP while the static lvalue address is restored to
;;; NC_PTR. Store one byte for char elements, both bytes for word elements.
emit_indexed_store:
	jsr emit_save_right_tmp
	bcc .failed
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #statementStaPtrEnd-statementStaPtr
	ldx #<statementStaPtr
	ldy #>statementStaPtr
	jsr emit_text
	bcc .failed
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	jsr emit_statement_address_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
	lda #statementStaPtrHighEnd-statementStaPtrHigh
	ldx #<statementStaPtrHigh
	ldy #>statementStaPtrHigh
	jsr emit_text
	bcc .failed

	lda statementElementType
	cmp #TYPE_CHAR
	beq .char
	lda #statementStoreWordEnd-statementStoreWord
	ldx #<statementStoreWord
	ldy #>statementStoreWord
	jmp emit_text
.char:
	lda #statementStoreCharEnd-statementStoreChar
	ldx #<statementStoreChar
	ldy #>statementStoreChar
	jmp emit_text
.failed:
	clc
	rts

;;; A/X is the condition result. Collapse both bytes to Z, then use the exact
;;; universal helper already used by expression comparisons. The real semantic
;;; destination is an absolute JMP; the relative BNE reaches only __nc_near_NNNN
;;; emitted adjacent to the branch.
emit_statement_false_jump:
	lda #statementTruthTestEnd-statementTruthTest
	ldx #<statementTruthTest
	ldy #>statementTruthTest
	jsr emit_text
	bcc .failed
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed emitted fragments
;;; ---------------------------------------------------------------------------

statementRts:		byte $09,'r','t','s',$0a
statementRtsEnd:
statementAddressSuffix:	byte '_','_','a'
statementAddressSuffixEnd:
statementLdaPtr:		byte $09,'l','d','a',' ','N','C','_','P','T','R',$0a
statementLdaPtrEnd:
statementLdaPtrHigh:	byte $09,'l','d','a',' ','N','C','_','P','T','R','+','1',$0a
statementLdaPtrHighEnd:
statementStaPtr:		byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
statementStaPtrEnd:
statementStaPtrHigh:	byte $09,'s','t','a',' ','N','C','_','P','T','R','+','1',$0a
statementStaPtrHighEnd:
statementTruthTest:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','x','a',$0a
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
statementTruthTestEnd:
statementStoreChar:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
statementStoreCharEnd:
statementStoreWord:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'s','t','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
statementStoreWordEnd: