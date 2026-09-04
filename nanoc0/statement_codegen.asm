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
	sta expressionValueLow
	lda statementTargetType
	sta expressionValueType
	lda statementTargetKind
	cmp #SYMBOL_ARRAY
	beq .array
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	lda #VALUE_CURRENT
	jmp .materialize
.persistent:
	lda #VALUE_PERSISTENT
	jmp .materialize
.array:
	lda #VALUE_ARRAY
.materialize:
	sta expressionValueKind
	jmp materialize_expression_word

;;; Exact byte `x = x +/- 1` updates the named object in place. Word values
;;; stay on the ordinary immediate arithmetic path, which already carries or
;;; borrows explicitly across A/X.
emit_direct_scalar_update:
	lda pendingOperator
	cmp #OP_SUB
	beq .subtract
	ldx #<statementIncSpace
	ldy #>statementIncSpace
	jmp emit_statement_target_line
.subtract:
	ldx #<statementDecSpace
	ldy #>statementDecSpace
emit_statement_target_line:
	jsr emit_string
	bcc .failed
	ldx statementTargetIndex
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	jsr emit_persistent_name
	jmp .newline
.current:
	jsr emit_current_name
.newline:
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_return_value:
	;;; Phase 1 C-defined functions return int. Delay promotion until this exact
	;;; observable boundary; a named char or byte comparison need not carry X
	;;; through the expression that produced it.
	jsr materialize_expression_word
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
	jsr materialize_expression_byte
	jmp .prepared
.word:
	jsr materialize_expression_word
.prepared:
	bcc .failed
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_string
	bcc .failed
	ldx statementTargetIndex
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda statementTargetType
	cmp #TYPE_CHAR
	beq .done
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_string
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

;;; The lvalue index/address must survive exactly one RHS expression. That is a
;;; short LIFO lifetime, so use the 6502 stack rather than generated static RAM.
emit_save_statement_index:
	jsr materialize_expression_byte
	bcc .failed
	ldx #<exprPha
	ldy #>exprPha
	jmp emit_string
.failed:
	clc
	rts

emit_save_statement_address:
	ldx #<statementPushPtr
	ldy #>statementPushPtr
	jmp emit_string

;;; Direct char[] stores keep only the byte index and use absolute,Y. A current
;;; char * reloads its named pointer after the RHS. Every other case restores the
;;; full effective address that was saved on the hardware stack.
emit_indexed_store:
	lda statementTargetKind
	cmp #STATEMENT_INDEX_ARRAY
	beq emit_indexed_array_store
	cmp #STATEMENT_INDEX_CURRENT_PTR
	beq emit_indexed_current_pointer_store

	;;; Preserve the completed RHS in NC_TMP while the saved address is popped.
	lda statementElementType
	cmp #TYPE_CHAR
	bne .wordValue
	jsr materialize_expression_byte
	bcc .failed
	jsr emit_save_right_byte_tmp
	jmp .restore
.wordValue:
	jsr materialize_expression_word
	bcc .failed
	jsr emit_save_right_tmp
	bcc .failed
.restore:
	ldx #<statementPopPtr
	ldy #>statementPopPtr
	jsr emit_string
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
	;;; PLA destroys the RHS A, so keep that one byte in NC_TMP for two
	;;; instructions while recovering Y.
	jsr materialize_expression_byte
	bcc .failed
	jsr emit_save_right_byte_tmp
	bcc .failed
	ldx #<statementPopIndexLoadTmp
	ldy #>statementPopIndexLoadTmp
	jsr emit_string
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
	jsr materialize_expression_byte
	bcc .failed
	jsr emit_save_right_byte_tmp
	bcc .failed
	jsr load_statement_target_base
	bcc .failed
	jsr emit_store_transient
	bcc .failed
	ldx #<statementPopIndexLoadTmp
	ldy #>statementPopIndexLoadTmp
	jsr emit_string
	bcc .failed
	ldx #<statementStoreCharY
	ldy #>statementStoreCharY
	jmp emit_string
.failed:
	clc
	rts

;;; A direct byte comparison is already in processor flags. Branch from those
;;; flags without manufacturing a Boolean. Other expressions are materialised only
;;; enough to answer C truth at this control-flow boundary.
emit_statement_false_jump:
	lda expressionValueKind
	cmp #VALUE_COND_EQ
	beq .eq
	cmp #VALUE_COND_NE
	beq .ne
	cmp #VALUE_COND_LT
	beq .lt
	cmp #VALUE_COND_GE
	beq .ge
	cmp #VALUE_COND_GT
	bne .notGt
	;;; GT requires both non-equality and carry-set. Each long test jumps to the
	;;; same false destination when its required flag is absent.
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_long_conditional_jump
	bcc .failed
	ldx #<exprBcs
	ldy #>exprBcs
	jmp emit_long_conditional_jump
.notGt:
	cmp #VALUE_COND_LE
	bne .notLe
	jmp emit_statement_le_false_jump
.notLe:

	lda expressionConditionBranch
	cmp #EXPR_CONDITION_BNE
	beq .bne
	cmp #EXPR_CONDITION_NONE
	bne .failed

	jsr expression_index_is_byte_domain
	bcc .word
	jsr materialize_expression_byte
	bcc .failed
	lda expressionConditionBranch
	cmp #EXPR_CONDITION_BNE
	beq .bne
	ldx #<statementByteTruthTest
	ldy #>statementByteTruthTest
	jsr emit_string
	bcc .failed
	jmp .bne
.word:
	jsr materialize_expression_word
	bcc .failed
	ldx #<statementTruthTest
	ldy #>statementTruthTest
	jsr emit_string
	bcc .failed
.bne:
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump
.eq:
	ldx #<exprBeq
	ldy #>exprBeq
	jmp emit_long_conditional_jump
.ne:
	ldx #<exprBne
	ldy #>exprBne
	jmp emit_long_conditional_jump
.lt:
	ldx #<exprBcc
	ldy #>exprBcc
	jmp emit_long_conditional_jump
.ge:
	ldx #<exprBcs
	ldy #>exprBcs
	jmp emit_long_conditional_jump
.failed:
	clc
	rts

;;; left <= right is true when carry is clear OR zero is set. Reuse the same
;;; nearby skip label as the ordinary branch-over-JMP emitter.
emit_statement_le_false_jump:
	jsr begin_conditional_jump
	ldx #<exprBcc
	ldy #>exprBcc
	jsr emit_branch_to_conditional_skip
	bcc .failed
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_branch_to_conditional_skip
	bcc .failed
	jmp finish_conditional_jump
.failed:
	jsr restore_conditional_target
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed emitted fragments
;;; ---------------------------------------------------------------------------

statementRts:		byte $09,'r','t','s',$0a,0
statementIncSpace:	byte $09,'i','n','c',' ',0
statementDecSpace:	byte $09,'d','e','c',' ',0
statementByteTruthTest:
	byte $09,'c','m','p',' ','#','$','0','0',$0a,0
statementTruthTest:
	byte $09,'s','t','x',' ','N','C','_','T','M','P',$0a
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a,0
statementPushPtr:
	byte $09,'l','d','a',' ','N','C','_','P','T','R',$0a
	byte $09,'p','h','a',$0a
	byte $09,'l','d','a',' ','N','C','_','P','T','R','+','1',$0a
	byte $09,'p','h','a',$0a,0
statementPopPtr:
	byte $09,'p','l','a',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R','+','1',$0a
	byte $09,'p','l','a',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a,0
statementPopIndexLoadTmp:
	byte $09,'p','l','a',$0a
	byte $09,'t','a','y',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a,0
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
