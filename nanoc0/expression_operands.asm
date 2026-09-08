;;; parse_expression_primary
;;; Emit one primary and advance currentToken beyond it. The routine records
;;; whether the result may be indexed and whether an array address is legal only
;;; as the base of an immediate index operation.
parse_expression_primary:
	lda #$00
	sta expressionIndexable
	sta expressionMustIndex
	lda currentTokenKind
	cmp #TOKEN_INTEGER
	bne .notInteger
	jmp .integer
.notInteger:
	cmp #TOKEN_CHARACTER
	bne .notCharacter
	jmp .character
.notCharacter:
	cmp #TOKEN_STRING
	bne .notString
	jmp .string
.notString:
	cmp #TOKEN_IDENTIFIER
	bne .badPrimary
	jmp .identifier
.badPrimary:
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail

.integer:
	lda currentTokenValue
	sta expressionValueLow
	lda currentTokenValue+1
	sta expressionValueHigh
	lda currentTokenType
	cmp #TOKEN_TYPE_UNSIGNED
	bne .integerSigned
	lda #TYPE_UNSIGNED
	jmp .integerTypeDone
.integerSigned:
	lda #TYPE_INT
.integerTypeDone:
	sta expressionValueType
	lda #VALUE_LITERAL
	sta expressionValueKind
	jsr parser_next
	bcc .integerFailed
	jmp .primaryDone
.integerFailed:
	rts

.character:
	lda currentTokenValue
	sta expressionValueLow
	lda #$00
	sta expressionValueHigh
	lda #TYPE_INT
	sta expressionValueType
	lda #VALUE_LITERAL
	sta expressionValueKind
	jsr parser_next
	bcc .characterFailed
	jmp .primaryDone
.characterFailed:
	rts

.string:
	jsr capture_string_literal
	bcs .stringCaptured
	rts
.stringCaptured:
	lda #VALUE_STRING
	sta expressionValueKind
	lda currentLiteralIndex
	sta expressionValueLow
	lda #$00
	sta expressionValueHigh
	lda #TYPE_CHAR_PTR
	sta expressionValueType
	lda #$01
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
	jsr parser_next
	bcc .stringFailed
	jmp .primaryDone
.stringFailed:
	rts

.identifier:
	jsr capture_primary_identifier
	bcs .advanceName
	rts
.advanceName:
	jsr parser_next
	bcs .nameAdvanced
	rts
.nameAdvanced:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_PERSISTENT
	bne .ordinaryScalar
	lda primarySymbolKind
	cmp #SYMBOL_FUNCTION
	beq .function
	cmp #SYMBOL_RUNTIME_FUNCTION
	beq .function
	cmp #SYMBOL_ARRAY
	beq .array

.ordinaryScalar:
	lda primarySymbolType
	sta expressionValueType
	cmp #TYPE_CHAR_PTR
	bne .loadScalar
	lda #INDEXABLE_POINTER
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
.loadScalar:
	jsr set_primary_scalar_operand
	bcs .primaryDone
	rts

.array:
	lda primarySymbolType
	sta expressionElementType
	lda #TYPE_CHAR_PTR
	sta expressionValueType
	lda #INDEXABLE_POINTER
	sta expressionIndexable
	lda #VALUE_ARRAY
	sta expressionValueKind
	lda primarySymbolIndex
	sta expressionValueLow
	lda #$00
	sta expressionValueHigh
	lda primarySymbolType
	cmp #TYPE_CHAR
	bne .arrayMustIndex
	lda currentTokenKind
	cmp #'['
	bne .primaryDone
	lda #INDEXABLE_FIXED_ARRAY
	sta expressionIndexable
	jmp .primaryDone
.arrayMustIndex:
	lda #$01
	sta expressionMustIndex
	jmp .primaryDone

.function:
	lda currentTokenKind
	cmp #'('
	beq .call
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.call:
	ldx primarySymbolIndex
	jsr expression_call_primary
	bcc .callFailed
	lda expressionNeedValue
	bne .callOpened
	jmp .primaryDone
.callOpened:
	sec
	rts
.callFailed:
	rts

.primaryDone:
	lda #$00
	sta expressionNeedValue
	sec
	rts

;;; Retain a scalar as a source operand rather than loading it. The assignment
;;; marker is only a parser fact for the exact x=x+/-1 spelling; the value itself
;;; remains an ordinary named operand until a consumer asks for it.
set_primary_scalar_operand:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	lda #VALUE_CURRENT
	bne .kind
.persistent:
	lda #VALUE_PERSISTENT
.kind:
	sta expressionValueKind
	lda primarySymbolIndex
	sta expressionValueLow
	lda #$00
	sta expressionValueHigh

	lda statementTargetKind
	cmp #STATEMENT_SCALAR_ASSIGNMENT
	bne .done
	lda operatorCount
	bne .done
	lda primarySymbolType
	cmp #TYPE_CHAR
	bne .done
	lda primarySymbolArea
	cmp statementTargetArea
	bne .done
	lda primarySymbolIndex
	cmp statementTargetIndex
	bne .done
	lda currentTokenKind
	cmp #'+'
	beq .self
	cmp #'-'
	bne .done
.self:
	lda #STATEMENT_SELF_UPDATE
	sta statementTargetKind
.done:
	sec
	rts

capture_primary_identifier:
	jsr lookup_symbol
	bcs .found
	lda #EXPR_UNDECLARED
	jmp expression_fail
.found:
	stx primarySymbolIndex
	lda lookupArea
	sta primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	ldx primarySymbolIndex
	lda persistentKind,x
	sta primarySymbolKind
	lda persistentType,x
	sta primarySymbolType
	sec
	rts
.current:
	lda #SYMBOL_GLOBAL
	sta primarySymbolKind
	ldx primarySymbolIndex
	lda currentType,x
	sta primarySymbolType
	sec
	rts

;;; Function calls are implemented by calls.asm below. Keeping the implementation
;;; after the ordinary expression code makes this primary a forward reference
;;; rather than placing the pending-call tables in the middle of the parser.

;;; Postfix indexing keeps the base in the same operand vocabulary as a binary
;;; left operand. A materialised base is pushed because the index expression may
;;; generate arbitrary code; a named pointer or fixed address remains nameable.
handle_postfix_index:
	lda currentTokenKind
	cmp #'['
	beq .index
	lda expressionMustIndex
	beq .done
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.done:
	sec
	rts
.index:
	lda expressionIndexable
	bne .allowed
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	beq .genericPointer
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.genericPointer:
	lda #TYPE_CHAR
	sta expressionElementType
.allowed:
	ldx operatorCount
	cpx #EXPR_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	;;; An older A/A-X value must survive the index evaluation and load. The
	;;; current base is handled separately just below.
	jsr preserve_pending_machine_value
	bcc .failed
	jsr prepare_current_operand_for_stack
	bcc .failed
	ldx operatorCount
	lda #OP_INDEX
	sta operatorKind,x
	lda expressionElementType
	sta operatorType,x
	jsr save_current_operand_in_operator
	inc operatorCount
	jsr parser_next
	bcc .failed
	lda #$01
	sta expressionNeedValue
	lda #$00
	sta expressionIndexable
	sta expressionMustIndex
	sec
.failed:
	rts

;;; push_simple_operator
;;; A=OP_GROUP or OP_NEG.
push_simple_operator:
	ldx operatorCount
	cpx #EXPR_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	sta operatorKind,x
	lda #VALUE_NONE
	sta operatorValueKind,x
	inc operatorCount
	sec
	rts

;;; A materialised operand has a real lifetime across an index expression. Put
;;; that lifetime on the 6502 stack; source-nameable operands need no generated
;;; storage at all.
prepare_current_operand_for_stack:
	lda expressionValueKind
	cmp #VALUE_A
	beq .pushByte
	cmp #VALUE_AX
	beq .pushWord
	cmp #VALUE_COND_EQ
	bcc .done
	cmp #VALUE_COND_LE+1
	bcs .done
	jsr materialize_expression_byte
	bcc .failed
.pushByte:
	ldx #<exprPha
	ldy #>exprPha
	jsr emit_string
	bcc .failed
	lda #VALUE_STACK_BYTE
	sta expressionValueKind
	sec
	rts
.pushWord:
	ldx #<exprPushWord
	ldy #>exprPushWord
	jsr emit_string
	bcc .failed
	lda #VALUE_STACK_WORD
	sta expressionValueKind
.done:
	sec
	rts
.failed:
	clc
	rts

save_current_operand_in_operator:
	ldx operatorCount
	lda expressionValueKind
	sta operatorValueKind,x
	lda expressionValueLow
	sta operatorValueLow,x
	lda expressionValueHigh
	sta operatorValueHigh,x
	rts

push_pending_binary:
	ldx operatorCount
	cpx #EXPR_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	;;; A/A-X can stay live while the RHS is merely a deferred literal or name.
	;;; If an older operator already owns A/A-X, however, this new nested binary
	;;; operation will eventually clobber it, so preserve that older value now.
	jsr preserve_pending_machine_value
	bcc .failed

	;;; Comparison flags are more fragile than A/A-X: ordinary compiler output
	;;; can change them before their eventual consumer, so keep their existing
	;;; short stack lifetime.
	lda expressionValueKind
	cmp #VALUE_COND_EQ
	bcc .save
	cmp #VALUE_COND_LE+1
	bcs .save
	jsr prepare_current_operand_for_stack
	bcc .failed
.save:
	ldx operatorCount
	lda pendingOperator
	sta operatorKind,x
	lda expressionValueType
	sta operatorType,x
	jsr save_current_operand_in_operator
	inc operatorCount
	sec
	rts
.failed:
	clc
	rts

;;; At most one older operator can own the generated machine's A/A-X value.
;;; Search from the nearest operator outward and move that value to the hardware
;;; stack immediately before some nested work is allowed to clobber it. Deferred
;;; literals and named operands never call this routine just to sit on the stack.
preserve_pending_machine_value:
	ldx operatorCount
.scan:
	cpx #$00
	beq .done
	dex
	lda operatorValueKind,x
	cmp #VALUE_A
	beq .byte
	cmp #VALUE_AX
	bne .scan

	;;; Once emission fails the expression is abandoned, so updating the
	;;; descriptor before emit_string avoids extra bookkeeping just for failure.
	lda #VALUE_STACK_WORD
	sta operatorValueKind,x
	ldx #<exprPushWord
	ldy #>exprPushWord
	jmp emit_string

.byte:
	lda #VALUE_STACK_BYTE
	sta operatorValueKind,x
	ldx #<exprPha
	ldy #>exprPha
	jmp emit_string
.done:
	sec
	rts

;;; Preserve values only when a call can actually invalidate them. Machine values
;;; cannot survive the JSR, and persistent scalars may be overwritten by the callee.
;;; One bottom-to-top scan preserves both kinds in reduction order so the later
;;; pops remain LIFO-correct.
preserve_pending_values_for_call:
	lda #$00
	sta preserveOperatorIndex
.loop:
	ldx preserveOperatorIndex
	cpx operatorCount
	beq .done
	lda operatorValueKind,x
	cmp #VALUE_PERSISTENT
	beq .preserve
	cmp #VALUE_A
	beq .preserve
	cmp #VALUE_AX
	bne .next
.preserve:
	;;; A/A-X already names the live machine value. The ordinary saved-operand
	;;; helper uses its C type to choose a byte or word push, just as it does for a
	;;; deferred scalar, while this scan preserves bottom-to-top stack order.
	sta reduceLeftKind
	cmp #VALUE_PERSISTENT
	bne .ordinaryType
	;;; OP_INDEX stores the element/result type in operatorType. A persistent
	;;; scalar under that marker is nevertheless the pointer base and must survive
	;;; a call as a full address, not as the eventual char element.
	lda operatorKind,x
	cmp #OP_INDEX
	bne .ordinaryType
	lda #TYPE_CHAR_PTR
	bne .haveType
.ordinaryType:
	lda operatorType,x
.haveType:
	sta reduceLeftType
	lda operatorValueLow,x
	sta reduceLeftLow
	lda operatorValueHigh,x
	sta reduceLeftHigh
	jsr emit_push_saved_operand
	bcc .failed
	ldx preserveOperatorIndex
	lda reduceLeftType
	cmp #TYPE_CHAR
	bne .word
	lda #VALUE_STACK_BYTE
	bne .store
.word:
	lda #VALUE_STACK_WORD
.store:
	sta operatorValueKind,x
.next:
	inc preserveOperatorIndex
	jmp .loop
.done:
	sec
	rts
.failed:
	clc
	rts

;;; Keep the compact x=x+/-1 source recognition from #74 without using it as a
;;; general expression fast path. The left operand is already saved in the normal
;;; operator entry, so a near miss simply leaves a captured literal as the RHS.
try_scalar_self_update_rhs:
	lda #RIGHT_START_NORMAL
	sta rightStartState
	lda statementTargetKind
	cmp #STATEMENT_SELF_UPDATE
	bne .done
	lda currentTokenKind
	cmp #TOKEN_INTEGER
	bne .notExact
	lda currentTokenValue
	eor #$01
	ora currentTokenValue+1
	bne .notExact
	lda currentTokenValue
	sta expressionValueLow
	lda #$00
	sta expressionValueHigh
	lda #TYPE_INT
	sta expressionValueType
	lda #VALUE_LITERAL
	sta expressionValueKind
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #';'
	bne .captured
	ldx operatorCount
	dex
	lda operatorType,x
	sta expressionValueType
	lda operatorValueKind,x
	sta expressionValueKind
	lda operatorValueLow,x
	sta expressionValueLow
	lda operatorValueHigh,x
	sta expressionValueHigh
	dec operatorCount
	lda #RIGHT_START_UPDATED
	sta rightStartState
	sec
	rts
.captured:
	lda #$00
	sta statementTargetKind
	lda #RIGHT_START_CAPTURED
	sta rightStartState
	lda #$00
	sta expressionNeedValue
	sec
	rts
.notExact:
	lda #$00
	sta statementTargetKind
.done:
	sec
	rts
.failed:
	clc
	rts

;;; Unary minus is right-associative because consecutive '-' markers remain
;;; stacked until a primary arrives, then reduce from the top.
reduce_unary_operators:
.loop:
	lda operatorCount
	beq .done
	tax
	dex
	lda operatorKind,x
	cmp #OP_NEG
	bne .done
	jsr reduce_unary_minus
	bcs .reduced
	rts
.reduced:
	dec operatorCount
	jmp .loop
.done:
	sec
	rts

reduce_unary_minus:
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	bne .integer
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.integer:
	;;; Unary code is destructive target work. Preserve any older binary value
	;;; immediately before emitting it, not when that older operator was parsed.
	jsr preserve_pending_machine_value
	bcc .emitFail
	jsr materialize_expression_word
	bcc .emitFail
	jsr emit_unary_minus
	bcs .emitted
.emitFail:
	jmp expression_emit_fail
.emitted:
	lda expressionValueType
	cmp #TYPE_UNSIGNED
	beq .typeDone
	lda #TYPE_INT
	sta expressionValueType
.typeDone:
	lda #$00
	sta expressionIndexable
	sec
	rts
