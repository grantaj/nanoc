;;; statements.asm
;;;
;;; Nano C Phase 1 executable statement parser and direct emitter.
;;;
;;; This is the statement analogue of expression.asm: one current token, one
;;; explicit bounded control stack, and assembly emitted as soon as a source
;;; construct is understood. There is no recursive block parser and no retained
;;; statement representation.
;;;
;;; A frame remembers only a concrete fact about source whose closing brace has
;;; not yet arrived:
;;;
;;;   BLOCK      only that an ordinary nested block is open
;;;   IF_TRUE    the false/join label for the open true body
;;;   IF_ELSE    the end label for the open else body
;;;   WHILE      loop-top and loop-end labels
;;;
;;; `break` searches those same frames downward for the nearest WHILE. The
;;; function body itself is depth zero, so `}` at depth zero ends the function.

CONTROL_STACK_CAPACITY = 16

CONTROL_BLOCK   = 1
CONTROL_IF_TRUE = 2
CONTROL_IF_ELSE = 3
CONTROL_WHILE   = 4

;;; parse_function_statements
;;; currentToken is the first executable token after function-entry locals.
;;; Carry set returns with currentToken already advanced beyond the function's
;;; closing brace.
parse_function_statements:
	jsr reset_statement_function_state

.loop:
	lda currentTokenKind
	cmp #TOKEN_EOF
	bne .notEof
	lda #PARSE_UNTERMINATED_FUNCTION
	jmp parser_fail
.notEof:
	jsr is_type_token
	bcc .notType
	lda #PARSE_LATE_LOCAL
	jmp parser_fail
.notType:
	lda currentTokenKind
	cmp #'}'
	bne .notClose
	jsr close_statement_body
	bcc .failed
	lda statementFunctionDone
	beq .loop
	sec
	rts
.notClose:
	cmp #'{' 
	bne .notBlock
	jsr begin_plain_block
	bcc .failed
	jmp .loop
.notBlock:
	cmp #TOKEN_IDENTIFIER
	bne .notIdentifier
	jsr parse_identifier_statement
	bcc .failed
	jmp .loop
.notIdentifier:
	cmp #TOKEN_KW_IF
	bne .notIf
	jsr parse_if_statement
	bcc .failed
	jmp .loop
.notIf:
	cmp #TOKEN_KW_WHILE
	bne .notWhile
	jsr parse_while_statement
	bcc .failed
	jmp .loop
.notWhile:
	cmp #TOKEN_KW_BREAK
	bne .notBreak
	jsr parse_break_statement
	bcc .failed
	jmp .loop
.notBreak:
	cmp #TOKEN_KW_RETURN
	bne .bad
	jsr parse_return_statement
	bcc .failed
	jmp .loop
.bad:
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.failed:
	clc
	rts

reset_statement_function_state:
	lda #$00
	sta controlDepth
	sta statementAddressAllocated
	sta statementFunctionDone
	rts

;;; ---------------------------------------------------------------------------
;;; Blocks and structured control
;;; ---------------------------------------------------------------------------

ensure_control_space:
	lda controlDepth
	cmp #CONTROL_STACK_CAPACITY
	bcc .space
	lda #PARSE_CONTROL_OVERFLOW
	jmp parser_fail
.space:
	sec
	rts

begin_plain_block:
	jsr ensure_control_space
	bcc .failed
	ldx controlDepth
	lda #CONTROL_BLOCK
	sta controlKind,x
	inc controlDepth
	jsr parser_next
.failed:
	rts

;;; A closing brace completes exactly the top frame. The mandatory braces of an
;;; if/while body are represented by the IF/WHILE frame itself; only an extra
;;; source block consumes a BLOCK frame.
close_statement_body:
	lda #$00
	sta statementFunctionDone
	lda controlDepth
	bne .nested
	lda #$01
	sta statementFunctionDone
	jmp parser_next
.nested:
	tax
	dex
	lda controlKind,x
	cmp #CONTROL_BLOCK
	bne .notBlock
	dec controlDepth
	jmp parser_next
.notBlock:
	cmp #CONTROL_IF_TRUE
	bne .notIfTrue
	jmp close_if_true_body
.notIfTrue:
	cmp #CONTROL_IF_ELSE
	bne .notIfElse
	jmp close_if_else_body
.notIfElse:
	cmp #CONTROL_WHILE
	bne .badFrame
	jmp close_while_body
.badFrame:
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail

parse_if_statement:
	jsr ensure_control_space
	bcc .failed
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'('
	beq .haveOpen
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveOpen:
	jsr parser_next
	bcc .failed
	jsr parse_condition_expression
	bcc .failed
	lda currentTokenKind
	cmp #')'
	beq .haveClose
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveClose:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'{' 
	beq .haveBody
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveBody:
	jsr reserve_generated_label
	ldx controlDepth
	lda emitLabelValue
	sta controlLabel0Lo,x
	lda emitLabelValue+1
	sta controlLabel0Hi,x
	lda #CONTROL_IF_TRUE
	sta controlKind,x
	inc controlDepth
	jsr emit_statement_false_jump
	bcc .emitFail
	jsr parser_next
.failed:
	rts
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

;;; The true-body `}` is current on entry. One token of lookahead is enough to
;;; decide the optional else. Without else, the false label is the join point and
;;; the token already read belongs to the surrounding construct.
close_if_true_body:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #TOKEN_KW_ELSE
	beq .elseBody

	ldx controlDepth
	dex
	lda controlLabel0Lo,x
	sta emitLabelValue
	lda controlLabel0Hi,x
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .emitFail
	dec controlDepth
	sec
	rts

.elseBody:
	jsr reserve_generated_label
	ldx controlDepth
	dex
	lda emitLabelValue
	sta controlLabel1Lo,x
	lda emitLabelValue+1
	sta controlLabel1Hi,x
	lda #CONTROL_IF_ELSE
	sta controlKind,x
	jsr emit_jump_label
	bcc .emitFail

	ldx controlDepth
	dex
	lda controlLabel0Lo,x
	sta emitLabelValue
	lda controlLabel0Hi,x
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .emitFail

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'{' 
	beq .openElse
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.openElse:
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

close_if_else_body:
	ldx controlDepth
	dex
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .emitFail
	dec controlDepth
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

parse_while_statement:
	jsr ensure_control_space
	bcc .failed

	ldx controlDepth
	jsr reserve_generated_label
	lda emitLabelValue
	sta controlLabel0Lo,x
	lda emitLabelValue+1
	sta controlLabel0Hi,x
	jsr emit_label_definition
	bcc .emitFail

	ldx controlDepth
	jsr reserve_generated_label
	lda emitLabelValue
	sta controlLabel1Lo,x
	lda emitLabelValue+1
	sta controlLabel1Hi,x

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'('
	beq .haveOpen
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveOpen:
	jsr parser_next
	bcc .failed
	jsr parse_condition_expression
	bcc .failed
	lda currentTokenKind
	cmp #')'
	beq .haveClose
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveClose:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'{' 
	beq .haveBody
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveBody:
	ldx controlDepth
	lda #CONTROL_WHILE
	sta controlKind,x
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1
	inc controlDepth
	jsr emit_statement_false_jump
	bcc .emitFail
	jsr parser_next
.failed:
	rts
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

close_while_body:
	ldx controlDepth
	dex
	lda controlLabel0Lo,x
	sta emitLabelValue
	lda controlLabel0Hi,x
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .emitFail

	ldx controlDepth
	dex
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .emitFail
	dec controlDepth
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

parse_break_statement:
	lda controlDepth
	sta statementSearchDepth
.search:
	lda statementSearchDepth
	beq .outside
	dec statementSearchDepth
	ldx statementSearchDepth
	lda controlKind,x
	cmp #CONTROL_WHILE
	bne .search
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #';'
	beq .emit
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.emit:
	jsr emit_jump_label
	bcc .emitFail
	jmp parser_next
.outside:
	lda #PARSE_BREAK_OUTSIDE_LOOP
	jmp parser_fail
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

;;; Conditions are ordinary expressions. The statement layer adds only the Phase
;;; 1 rule that pointer values are not conditions.
parse_condition_expression:
	jsr parse_expression
	bcs .parsed
	jmp statement_expression_failed
.parsed:
	lda expressionValueType
	jsr type_is_integer
	bcs .ok
	lda #PARSE_BAD_CONDITION
	jmp parser_fail
.ok:
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Return
;;; ---------------------------------------------------------------------------

parse_return_statement:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #';'
	bne .expression
	lda #PARSE_BAD_RETURN
	jmp parser_fail
.expression:
	jsr parse_expression
	bcs .parsed
	jmp statement_expression_failed
.parsed:
	lda expressionValueType
	jsr type_is_integer
	bcc .badType
	lda currentTokenKind
	cmp #';'
	beq .emit
	lda #PARSE_BAD_RETURN
	jmp parser_fail
.emit:
	lda #statementRtsEnd-statementRts
	ldx #<statementRts
	ldy #>statementRts
	jsr emit_text
	bcc .emitFail
	jmp parser_next
.badType:
	lda #PARSE_BAD_RETURN
	jmp parser_fail
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Identifier-led statements
;;; ---------------------------------------------------------------------------

;;; Resolve the identifier before replacing the reusable token. Only the small
;;; semantic identity that later tokens need is retained.
parse_identifier_statement:
	jsr lookup_symbol
	bcs .found
	lda #PARSE_UNDECLARED
	jmp parser_fail
.found:
	stx statementTargetIndex
	lda lookupArea
	sta statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	ldx statementTargetIndex
	lda persistentKind,x
	sta statementTargetKind
	lda persistentType,x
	sta statementTargetType
	jmp .advance
.current:
	lda #SYMBOL_GLOBAL
	sta statementTargetKind
	ldx statementTargetIndex
	lda currentType,x
	sta statementTargetType
.advance:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'='
	bne .notScalar
	jmp parse_scalar_assignment
.notScalar:
	cmp #'['
	bne .notIndexed
	jmp parse_indexed_assignment
.notIndexed:
	cmp #'('
	bne .bad
	jmp parse_call_statement_hook
.bad:
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.failed:
	clc
	rts

parse_scalar_assignment:
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	beq .targetOk
	lda statementTargetKind
	cmp #SYMBOL_GLOBAL
	beq .targetOk
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.targetOk:
	jsr parser_next
	bcc .failed
	jsr parse_expression
	bcs .rhsParsed
	jmp statement_expression_failed
.rhsParsed:
	lda currentTokenKind
	cmp #';'
	beq .store
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.store:
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	ldx statementTargetIndex
	jsr emit_store_current_value
	bcc .emitFail
	jmp parser_next
.persistent:
	jsr emit_store_persistent_value
	bcc .emitFail
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

;;; Indexed assignment reuses #55's effective-address emitter rather than
;;; carrying a second copy of 16-bit scaling/addition here. After the index has
;;; been evaluated, its A/X value is parked in NC_TMP while the named base is
;;; loaded and saved in the normal expression spill slot expected by
;;; emit_index_load. That existing emitter forms NC_PTR exactly as for an indexed
;;; rvalue. Its final load is deliberately harmless: the statement immediately
;;; saves NC_PTR and then evaluates the RHS, so the loaded old element value is
;;; discarded. A few generated instructions buy one authoritative address path.
parse_indexed_assignment:
	jsr validate_indexed_target
	bcc .badTarget
	jsr parser_next
	bcc .failed
	jsr parse_expression
	bcs .indexParsed
	jmp statement_expression_failed
.indexParsed:
	lda expressionValueType
	jsr type_is_integer
	bcc .badTarget
	lda currentTokenKind
	cmp #']'
	beq .address
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.address:
	jsr emit_statement_index_address
	bcs .addressDone
	lda expressionError
	beq .emitFail
	jmp statement_expression_failed
.addressDone:
	jsr ensure_statement_address_slot
	bcc .failed
	jsr emit_save_statement_address
	bcc .emitFail

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'='
	beq .equals
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.equals:
	jsr parser_next
	bcc .failed
	jsr parse_expression
	bcs .rhsParsed
	jmp statement_expression_failed
.rhsParsed:
	lda currentTokenKind
	cmp #';'
	beq .store
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.store:
	jsr emit_indexed_store
	bcc .emitFail
	jmp parser_next
.badTarget:
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

validate_indexed_target:
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	lda statementTargetType
	cmp #TYPE_CHAR_PTR
	bne .bad
	lda #TYPE_CHAR
	sta statementElementType
	sec
	rts
.persistent:
	lda statementTargetKind
	cmp #SYMBOL_ARRAY
	beq .array
	cmp #SYMBOL_GLOBAL
	bne .bad
	lda statementTargetType
	cmp #TYPE_CHAR_PTR
	bne .bad
	lda #TYPE_CHAR
	sta statementElementType
	sec
	rts
.array:
	lda statementTargetType
	cmp #TYPE_CHAR
	beq .arrayTypeOk
	cmp #TYPE_INT
	beq .arrayTypeOk
	cmp #TYPE_UNSIGNED
	bne .bad
.arrayTypeOk:
	sta statementElementType
	sec
	rts
.bad:
	clc
	rts

;;; Index is in target A/X on entry. The normal expression spill stack is idle
;;; because parse_expression has completed, so one spill may temporarily hold
;;; the lvalue base. Restore depth immediately after the #55 emitter has used it.
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

	lda #exprLoadTmpResultEnd-exprLoadTmpResult
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jsr emit_text
	bcc .releaseFailed
	jsr emit_index_load
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

;;; One two-byte saved effective address is enough for every indexed assignment
;;; in a function: it is live only while that statement's RHS is evaluated.
ensure_statement_address_slot:
	lda statementAddressAllocated
	beq .allocate
	sec
	rts
.allocate:
	lda #$02
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcs .allocated
	lda #PARSE_BSS_OVERFLOW
	jmp parser_fail
.allocated:
	jsr emit_statement_address_definition
	bcs .emitted
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.emitted:
	lda #$01
	sta statementAddressAllocated
	sec
	rts

;;; The statement call form goes through the one call-primary seam already left
;;; by #55. #57 replaces that seam with pending-call state; this file does not
;;; learn a temporary argument grammar.
parse_call_statement_hook:
	lda statementTargetArea
	cmp #SYMBOL_AREA_PERSISTENT
	bne .bad
	lda statementTargetKind
	cmp #SYMBOL_FUNCTION
	beq .call
	cmp #SYMBOL_RUNTIME_FUNCTION
	bne .bad
.call:
	lda statementTargetIndex
	sta primarySymbolIndex
	lda statementTargetArea
	sta primarySymbolArea
	lda statementTargetKind
	sta primarySymbolKind
	lda statementTargetType
	sta primarySymbolType
	lda #EXPR_OK
	sta expressionError
	ldx statementTargetIndex
	jsr expression_call_primary
	bcs .callDone
	jmp statement_expression_failed
.callDone:
	lda currentTokenKind
	cmp #';'
	beq .done
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.done:
	jmp parser_next
.bad:
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail

;;; Expression failures retain their precise expressionError. Scanner failure is
;;; already layered through parserError/scannerError and must not be relabelled.
statement_expression_failed:
	lda parserError
	cmp #PARSE_SCANNER_ERROR
	beq .scanner
	lda #PARSE_EXPRESSION_ERROR
	jmp parser_fail
.scanner:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Statement target-code emission
;;; ---------------------------------------------------------------------------

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
;;; universal helper already used by expression comparisons. The real false
;;; destination is the absolute JMP; the relative BNE reaches only the helper's
;;; immediately adjacent skip label.
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

;;; ---------------------------------------------------------------------------
;;; Compiler statement state
;;; ---------------------------------------------------------------------------

;;; Fixed control stack: 16 frames * (kind + two 16-bit label slots) = 80 bytes,
;;; plus the one-byte depth. IF_TRUE versus IF_ELSE is explicit in the kind byte;
;;; no enum ordering carries semantics. BLOCK frames use only controlKind.
controlDepth:		byte 0
controlKind:		ds CONTROL_STACK_CAPACITY
controlLabel0Lo:	ds CONTROL_STACK_CAPACITY
controlLabel0Hi:	ds CONTROL_STACK_CAPACITY
controlLabel1Lo:	ds CONTROL_STACK_CAPACITY
controlLabel1Hi:	ds CONTROL_STACK_CAPACITY

statementFunctionDone:	byte 0
statementSearchDepth:	byte 0
statementTargetIndex:	byte 0
statementTargetArea:	byte SYMBOL_AREA_NONE
statementTargetKind:	byte 0
statementTargetType:	byte TYPE_INT
statementElementType:	byte TYPE_CHAR
statementAddressAllocated:	byte 0
