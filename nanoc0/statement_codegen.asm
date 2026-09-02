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

emit_return_value:
	ldx #<statementRts
	ldy #>statementRts
	jmp emit_string

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

	jsr emit_save_right_tmp
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

;;; A/X is the condition result. Comparisons deliberately leave Z matching their
;;; canonical 0/1 result, so consuming that flag is the natural 6502 path. A
;;; plain char needs only one CMP. Genuine 16-bit values retain the explicit
;;; high/low collapse. In every case BNE skips the adjacent false-target JMP when
;;; the condition is true.
emit_statement_false_jump:
	lda expressionTruthInZ
	bne .branch
	lda expressionValueType
	cmp #TYPE_CHAR
	bne .word
	ldx #<statementByteTruthTest
	ldy #>statementByteTruthTest
	jsr emit_string
	bcc .failed
	jmp .branch
.word:
	ldx #<statementTruthTest
	ldy #>statementTruthTest
	jsr emit_string
	bcc .failed
.branch:
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

statementRts:		byte $09,'r','t','s',$0a,0
statementAddressSuffix:	byte '_','_','a',0
statementLdySpace:	byte $09,'l','d','y',' ',0
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
