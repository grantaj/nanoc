;;; expressions.asm
;;;
;;; Nano C Phase 1 non-recursive expression parser and direct assembly emitter.
;;;
;;; The scanner still owns exactly one reusable token. This file adds one
;;; bounded operator stack; it does not build an AST, RPN stream, or other
;;; retained expression representation. Binary left operands are spilled to
;;; fixed per-function NC_BSS words as soon as an operator is pushed. Reducing
;;; the operator emits ordinary `ass` source immediately and leaves the runtime
;;; value in the machine convention A=low, X=high.
;;;
;;; Stack entries have four parallel bytes:
;;;   operatorStackOp      binary operator or PAREN/INDEX marker
;;;   operatorStackType    binary left type, or indexed-base element/type
;;;   operatorStackValue   spill depth, or indexed-base symbol index
;;;   operatorStackArea    unused for binary, symbol area for INDEX
;;;
;;; INDEX is a marker on this same stack. That lets `a[b + c]`, nested indexing,
;;; and parentheses share one non-recursive delimiter mechanism.
;;;
;;; Generated names deliberately retain source context:
;;;   persistent C object/function  __c_<source-name>
;;;   current param/local slot      __c_<function>__vNN
;;;   expression spill              __c_<function>__sNN
;;;   deferred string               __nc_strNN
;;;
;;; Only two low-level output hooks are external:
;;;   emit_output_byte   A=one output byte
;;;   emit_output_bytes  A=length, X/Y=address
;;; Both return carry set on success. They may clobber A/X/Y and the two Nano C
;;; zero-page scratch pairs; expression state that survives a hook lives in
;;; ordinary compiler storage.

EXPRESSION_STACK_CAPACITY        = 32
EXPRESSION_LITERAL_COUNT_CAPACITY = 32
EXPRESSION_LITERAL_POOL_CAPACITY  = 512

EXPR_OK                  = 0
EXPR_SCANNER_ERROR       = 1
EXPR_EXPECTED_VALUE      = 2
EXPR_UNEXPECTED_TOKEN    = 3
EXPR_STACK_OVERFLOW      = 4
EXPR_UNMATCHED_DELIMITER = 5
EXPR_UNDECLARED          = 6
EXPR_TYPE_MISMATCH       = 7
EXPR_EMIT_ERROR          = 8
EXPR_BSS_OVERFLOW        = 9
EXPR_LITERAL_CAPACITY    = 10
EXPR_CALL_UNAVAILABLE    = 11

OP_PAREN = 1
OP_INDEX = 2
OP_NEG   = 3
OP_MUL   = 4
OP_ADD   = 5
OP_SUB   = 6
OP_SHL   = 7
OP_SHR   = 8
OP_LT    = 9
OP_LE    = 10
OP_GT    = 11
OP_GE    = 12
OP_EQ    = 13
OP_NE    = 14
OP_AND   = 15
OP_OR    = 16

;;; ---------------------------------------------------------------------------
;;; Public expression state/reset
;;; ---------------------------------------------------------------------------

;;; reset_expression_unit
;;; Reset state that belongs to one translation unit. Per-function spill slots
;;; are reset separately because the literal/label pools span all functions.
reset_expression_unit:
	lda #$00
	sta expressionLabelCounter
	sta expressionLabelCounter+1
	sta expressionLiteralCount
	sta expressionLiteralPoolUsed
	sta expressionLiteralPoolUsed+1
	sta expressionNeedsMultiply
	rts

;;; reset_expression_function
;;; Spill depth N is allocated only the first time this function needs it and is
;;; reused by every later expression in the same function.
reset_expression_function:
	lda #$00
	sta expressionSpillAllocated
	rts

;;; parse_expression
;;; currentToken is the first token of an expression.
;;; Carry set: expression emitted, exprValueType is valid, and currentToken is
;;;            the unconsumed terminator (`;`, `,`, outer `)`/`]`, or EOF).
;;; Carry clear: expressionError contains EXPR_*.
parse_expression:
	lda #EXPR_OK
	sta expressionError
	lda #$00
	sta operatorStackCount
	sta activeSpillDepth
	sta expressionDone
	lda #$01
	sta expressionExpectOperand

.loop:
	lda expressionExpectOperand
	beq .afterValue
	jsr expression_parse_operand
	bcc .failed
	jmp .checkDone
.afterValue:
	jsr expression_parse_after_value
	bcc .failed
.checkDone:
	lda expressionDone
	beq .loop
	sec
	rts
.failed:
	clc
	rts

expression_fail:
	sta expressionError
	clc
	rts

expression_next:
	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_ERROR
	bne .ok
	lda #EXPR_SCANNER_ERROR
	jmp expression_fail
.ok:
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Operand / primary recognition
;;; ---------------------------------------------------------------------------

expression_parse_operand:
	lda currentTokenKind
	cmp #'-'
	beq .unaryMinus
	cmp #'('
	beq .parenthesis
	cmp #TOKEN_INTEGER
	beq .integer
	cmp #TOKEN_CHARACTER
	beq .character
	cmp #TOKEN_STRING
	beq .string
	cmp #TOKEN_IDENTIFIER
	beq .identifier
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail

.unaryMinus:
	lda #OP_NEG
	jsr push_simple_operator
	bcc .failed
	jsr expression_next
	rts
.parenthesis:
	lda #OP_PAREN
	jsr push_simple_operator
	bcc .failed
	jsr expression_next
	rts
.integer:
	lda currentTokenValue
	sta emitValueLo
	lda currentTokenValue+1
	sta emitValueHi
	lda currentTokenType
	cmp #TOKEN_TYPE_UNSIGNED
	beq .integerUnsigned
	lda #TYPE_INT
	bne .integerType
.integerUnsigned:
	lda #TYPE_UNSIGNED
.integerType:
	sta exprValueType
	jsr emit_immediate_value
	bcc .failed
	jsr expression_next
	bcc .failed
	jmp expression_primary_complete
.character:
	lda currentTokenValue
	sta emitValueLo
	lda #$00
	sta emitValueHi
	lda #TYPE_INT
	sta exprValueType
	jsr emit_immediate_value
	bcc .failed
	jsr expression_next
	bcc .failed
	jmp expression_primary_complete
.string:
	jsr retain_string_literal
	bcc .failed
	stx primarySymbolIndex
	lda #TYPE_CHAR_PTR
	sta exprValueType
	jsr emit_string_address
	bcc .failed
	jsr expression_next
	bcc .failed
	jmp expression_primary_complete
.identifier:
	jsr expression_identifier_primary
	rts
.failed:
	clc
	rts

expression_primary_complete:
	lda #$00
	sta expressionExpectOperand
	jsr reduce_prefix_operators
	rts

expression_identifier_primary:
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
	lda persistentType,x
	sta primarySymbolType
	lda persistentKind,x
	sta primarySymbolKind
	jmp .advance
.current:
	ldx primarySymbolIndex
	lda currentType,x
	sta primarySymbolType
	lda #SYMBOL_GLOBAL
	sta primarySymbolKind
.advance:
	jsr expression_next
	bcc .failed
	lda currentTokenKind
	cmp #'['
	beq .index

	lda primarySymbolArea
	cmp #SYMBOL_AREA_PERSISTENT
	bne .scalar
	ldx primarySymbolIndex
	lda persistentKind,x
	cmp #SYMBOL_FUNCTION
	beq .function
	cmp #SYMBOL_RUNTIME_FUNCTION
	beq .function
	cmp #SYMBOL_ARRAY
	bne .scalar
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq .charArrayAddress
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.charArrayAddress:
	ldx primarySymbolIndex
	jsr emit_persistent_address
	bcc .failed
	lda #TYPE_CHAR_PTR
	sta exprValueType
	jmp expression_primary_complete

.function:
	lda currentTokenKind
	cmp #'('
	beq .call
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.call:
	ldx primarySymbolIndex
	jsr expression_call_primary
	bcc .failed
	jmp expression_primary_complete

.scalar:
	lda primarySymbolType
	sta exprValueType
	jsr emit_primary_symbol_load
	bcc .failed
	jmp expression_primary_complete

.index:
	jsr validate_index_base
	bcc .failed
	jsr push_index_marker
	bcc .failed
	jsr expression_next
	bcc .failed
	lda #$01
	sta expressionExpectOperand
	sec
	rts
.failed:
	clc
	rts

;;; Narrow #57 integration point. It is deliberately not a second temporary call
;;; parser: until the call issue lands, a call primary reports that capability as
;;; unavailable. #57 replaces this body with the one real pending-call parser.
expression_call_primary:
	lda #EXPR_CALL_UNAVAILABLE
	jmp expression_fail

validate_index_base:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	lda primarySymbolType
	cmp #TYPE_CHAR_PTR
	beq .ok
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.persistent:
	ldx primarySymbolIndex
	lda persistentKind,x
	cmp #SYMBOL_ARRAY
	beq .ok
	cmp #SYMBOL_GLOBAL
	bne .bad
	lda persistentType,x
	cmp #TYPE_CHAR_PTR
	beq .ok
.bad:
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.ok:
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; After-value parsing, precedence and delimiters
;;; ---------------------------------------------------------------------------

expression_parse_after_value:
	lda currentTokenKind
	cmp #')'
	beq .closeParen
	cmp #']'
	beq .closeIndex
	cmp #';'
	beq .finish
	cmp #','
	beq .finish
	cmp #TOKEN_EOF
	beq .finish
	jsr token_to_binary_operator
	bcc .unexpected
	sta incomingOperator
	jsr push_binary_operator
	rts
.closeParen:
	jsr close_parenthesis_or_finish
	rts
.closeIndex:
	jsr close_index_or_finish
	rts
.finish:
	jsr finish_expression
	rts
.unexpected:
	lda #EXPR_UNEXPECTED_TOKEN
	jmp expression_fail

;;; token_to_binary_operator
;;; A=currentTokenKind on entry. Carry set with A=OP_* for a binary operator.
token_to_binary_operator:
	cmp #'*'
	beq .mul
	cmp #'+'
	beq .add
	cmp #'-'
	beq .sub
	cmp #'<'
	beq .lt
	cmp #'>'
	beq .gt
	cmp #'&'
	beq .and
	cmp #'|'
	beq .or
	cmp #TOKEN_SHL
	beq .shl
	cmp #TOKEN_SHR
	beq .shr
	cmp #TOKEN_LE
	beq .le
	cmp #TOKEN_GE
	beq .ge
	cmp #TOKEN_EQ
	beq .eq
	cmp #TOKEN_NE
	beq .ne
	clc
	rts
.mul:	lda #OP_MUL
	bne .yes
.add:	lda #OP_ADD
	bne .yes
.sub:	lda #OP_SUB
	bne .yes
.shl:	lda #OP_SHL
	bne .yes
.shr:	lda #OP_SHR
	bne .yes
.lt:	lda #OP_LT
	bne .yes
.le:	lda #OP_LE
	bne .yes
.gt:	lda #OP_GT
	bne .yes
.ge:	lda #OP_GE
	bne .yes
.eq:	lda #OP_EQ
	bne .yes
.ne:	lda #OP_NE
	bne .yes
.and:	lda #OP_AND
	bne .yes
.or:	lda #OP_OR
.yes:
	sec
	rts

push_simple_operator:
	ldx operatorStackCount
	cpx #EXPRESSION_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	sta operatorStackOp,x
	inc operatorStackCount
	sec
	rts

push_index_marker:
	ldx operatorStackCount
	cpx #EXPRESSION_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	lda #OP_INDEX
	sta operatorStackOp,x
	lda primarySymbolType
	sta operatorStackType,x
	lda primarySymbolIndex
	sta operatorStackValue,x
	lda primarySymbolArea
	sta operatorStackArea,x
	inc operatorStackCount
	sec
	rts

push_binary_operator:
	lda incomingOperator
	jsr operator_precedence
	sta incomingPrecedence
.reduce:
	lda operatorStackCount
	beq .spill
	tax
	dex
	lda operatorStackOp,x
	cmp #OP_PAREN
	beq .spill
	cmp #OP_INDEX
	beq .spill
	jsr operator_precedence
	cmp incomingPrecedence
	bcc .spill
	jsr reduce_top_operator
	bcc .failed
	jmp .reduce

.spill:
	lda activeSpillDepth
	jsr ensure_expression_spill
	bcc .failed
	lda activeSpillDepth
	sta reductionSpillDepth
	jsr emit_store_spill
	bcc .failed

	ldx operatorStackCount
	cpx #EXPRESSION_STACK_CAPACITY
	bcc .stackSpace
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.stackSpace:
	lda incomingOperator
	sta operatorStackOp,x
	lda exprValueType
	sta operatorStackType,x
	lda activeSpillDepth
	sta operatorStackValue,x
	lda #$00
	sta operatorStackArea,x
	inc operatorStackCount
	inc activeSpillDepth
	jsr expression_next
	bcc .failed
	lda #$01
	sta expressionExpectOperand
	sec
	rts
.failed:
	clc
	rts

operator_precedence:
	cmp #OP_NEG
	beq .p9
	cmp #OP_MUL
	beq .p8
	cmp #OP_ADD
	beq .p7
	cmp #OP_SUB
	beq .p7
	cmp #OP_SHL
	beq .p6
	cmp #OP_SHR
	beq .p6
	cmp #OP_LT
	beq .p5
	cmp #OP_LE
	beq .p5
	cmp #OP_GT
	beq .p5
	cmp #OP_GE
	beq .p5
	cmp #OP_EQ
	beq .p4
	cmp #OP_NE
	beq .p4
	cmp #OP_AND
	beq .p3
	lda #$02			; OP_OR
	rts
.p3:	lda #$03
	rts
.p4:	lda #$04
	rts
.p5:	lda #$05
	rts
.p6:	lda #$06
	rts
.p7:	lda #$07
	rts
.p8:	lda #$08
	rts
.p9:	lda #$09
	rts

close_parenthesis_or_finish:
	jsr reduce_until_marker
	bcc .outerTerminator
	cmp #OP_PAREN
	beq .matched
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.matched:
	dec operatorStackCount
	jsr expression_next
	bcc .failed
	jsr reduce_prefix_operators
	rts
.outerTerminator:
	jsr finish_expression
	rts
.failed:
	clc
	rts

close_index_or_finish:
	jsr reduce_until_marker
	bcc .outerTerminator
	cmp #OP_INDEX
	beq .matched
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.matched:
	ldx operatorStackCount
	dex
	lda operatorStackType,x
	sta effectiveElementType
	lda operatorStackValue,x
	sta effectiveBaseIndex
	lda operatorStackArea,x
	sta effectiveBaseArea
	dec operatorStackCount

	lda exprValueType
	cmp #TYPE_CHAR_PTR
	bne .numericIndex
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.numericIndex:
	jsr configure_effective_base
	bcc .failed
	jsr emit_effective_address
	bcc .failed
	jsr emit_effective_load
	bcc .failed
	jsr expression_next
	bcc .failed
	jsr reduce_prefix_operators
	rts
.outerTerminator:
	jsr finish_expression
	rts
.failed:
	clc
	rts

reduce_until_marker:
.loop:
	lda operatorStackCount
	beq .none
	tax
	dex
	lda operatorStackOp,x
	cmp #OP_PAREN
	beq .marker
	cmp #OP_INDEX
	beq .marker
	jsr reduce_top_operator
	bcc .failed
	jmp .loop
.marker:
	sec
	rts
.none:
	clc
	rts
.failed:
	clc
	rts

finish_expression:
	lda expressionExpectOperand
	beq .reduce
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail
.reduce:
	lda operatorStackCount
	beq .done
	tax
	dex
	lda operatorStackOp,x
	cmp #OP_PAREN
	beq .unmatched
	cmp #OP_INDEX
	beq .unmatched
	jsr reduce_top_operator
	bcc .failed
	jmp .reduce
.unmatched:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.done:
	lda activeSpillDepth
	beq .balanced
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.balanced:
	lda #$01
	sta expressionDone
	sec
	rts
.failed:
	clc
	rts

reduce_prefix_operators:
.loop:
	lda operatorStackCount
	beq .done
	tax
	dex
	lda operatorStackOp,x
	cmp #OP_NEG
	bne .done
	dec operatorStackCount
	lda exprValueType
	cmp #TYPE_CHAR_PTR
	bne .typeOk
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail
.typeOk:
	cmp #TYPE_CHAR
	bne .emit
	lda #TYPE_INT
	sta exprValueType
.emit:
	jsr emit_unary_negate
	bcc .failed
	jmp .loop
.done:
	sec
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Reduction and type rules
;;; ---------------------------------------------------------------------------

reduce_top_operator:
	lda operatorStackCount
	beq .bad
	tax
	dex
	lda operatorStackOp,x
	sta reductionOperator
	cmp #OP_NEG
	beq .prefix
	cmp #OP_PAREN
	beq .bad
	cmp #OP_INDEX
	beq .bad
	lda operatorStackType,x
	sta reductionLeftType
	lda operatorStackValue,x
	sta reductionSpillDepth
	lda exprValueType
	sta reductionRightType
	dec operatorStackCount
	dec activeSpillDepth
	jsr prepare_binary_types
	bcc .failed

	lda reductionOperator
	cmp #OP_MUL
	beq .mul
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .sub
	cmp #OP_SHL
	beq .shl
	cmp #OP_SHR
	beq .shr
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
	cmp #OP_EQ
	beq .compare
	cmp #OP_NE
	beq .compare
	cmp #OP_LT
	beq .compare
	cmp #OP_LE
	beq .compare
	cmp #OP_GT
	beq .compare
	cmp #OP_GE
	beq .compare
	jmp .bad
.mul:
	jsr emit_binary_multiply
	jmp .emitted
.add:
	jsr emit_binary_add
	jmp .emitted
.sub:
	jsr emit_binary_subtract
	jmp .emitted
.shl:
	lda #$00
	jsr emit_binary_shift
	jmp .emitted
.shr:
	lda #$01
	jsr emit_binary_shift
	jmp .emitted
.and:
	jsr emit_binary_and
	jmp .emitted
.or:
	jsr emit_binary_or
	jmp .emitted
.compare:
	jsr emit_binary_compare
.emitted:
	bcc .failed
	lda reductionResultType
	sta exprValueType
	sec
	rts
.prefix:
	jsr reduce_prefix_operators
	rts
.bad:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.failed:
	clc
	rts

prepare_binary_types:
	lda reductionLeftType
	cmp #TYPE_CHAR_PTR
	beq .leftPointer
	lda reductionRightType
	cmp #TYPE_CHAR_PTR
	beq .bad
	jsr normalize_binary_types
	bcc .bad
	lda reductionOperator
	cmp #OP_EQ
	beq .comparison
	cmp #OP_NE
	beq .comparison
	cmp #OP_LT
	beq .comparison
	cmp #OP_LE
	beq .comparison
	cmp #OP_GT
	beq .comparison
	cmp #OP_GE
	beq .comparison
	lda reductionCombinedType
	sta reductionResultType
	sec
	rts
.comparison:
	lda #TYPE_INT
	sta reductionResultType
	sec
	rts
.leftPointer:
	lda reductionOperator
	cmp #OP_ADD
	bne .bad
	lda reductionRightType
	cmp #TYPE_CHAR_PTR
	beq .bad
	lda #TYPE_CHAR_PTR
	sta reductionResultType
	lda #$00
	sta reductionUnsigned
	sec
	rts
.bad:
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail

normalize_binary_types:
	lda reductionLeftType
	cmp #TYPE_CHAR
	bne .leftReady
	lda #TYPE_INT
.leftReady:
	sta normalizedLeftType
	lda reductionRightType
	cmp #TYPE_CHAR
	bne .rightReady
	lda #TYPE_INT
.rightReady:
	sta normalizedRightType
	lda normalizedLeftType
	cmp #TYPE_UNSIGNED
	beq .unsigned
	lda normalizedRightType
	cmp #TYPE_UNSIGNED
	beq .unsigned
	lda #TYPE_INT
	sta reductionCombinedType
	lda #$00
	sta reductionUnsigned
	sec
	rts
.unsigned:
	lda #TYPE_UNSIGNED
	sta reductionCombinedType
	lda #$01
	sta reductionUnsigned
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Spill allocation
;;; ---------------------------------------------------------------------------

ensure_expression_spill:
	cmp expressionSpillAllocated
	bcc .ready
	beq .allocate
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.allocate:
	pha
	lda #$02
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcs .allocated
	pla
	lda #EXPR_BSS_OVERFLOW
	jmp expression_fail
.allocated:
	pla
	sta reductionSpillDepth
	jsr emit_spill_definition
	bcc .failed
	inc expressionSpillAllocated
.ready:
	sec
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Index-address configuration. emit_effective_address is intentionally public
;;; for #56 indexed stores: set these four bytes, leave index in runtime A/X,
;;; call it, and NC_PTR becomes the full effective address.
;;; ---------------------------------------------------------------------------

configure_effective_base:
	lda effectiveBaseArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	lda #$00
	sta effectiveBaseIsArray
	lda #TYPE_CHAR
	sta effectiveElementType
	sec
	 rts
.persistent:
	ldx effectiveBaseIndex
	lda persistentKind,x
	cmp #SYMBOL_ARRAY
	beq .array
	cmp #SYMBOL_GLOBAL
	bne .bad
	lda persistentType,x
	cmp #TYPE_CHAR_PTR
	bne .bad
	lda #$00
	sta effectiveBaseIsArray
	lda #TYPE_CHAR
	sta effectiveElementType
	sec
	rts
.array:
	lda #$01
	sta effectiveBaseIsArray
	lda persistentType,x
	sta effectiveElementType
	sec
	rts
.bad:
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail

;;; ---------------------------------------------------------------------------
;;; Direct generated-code emitters
;;; ---------------------------------------------------------------------------

emit_immediate_value:
	jsr emit_txt_lda_imm
	bcc .failed
	lda emitValueLo
	jsr emit_hex_byte
	bcc .failed
	jsr emit_txt_ldx_imm
	bcc .failed
	lda emitValueHi
	jsr emit_hex_byte
	bcc .failed
	jsr emit_txt_nl
	rts
.failed:
	clc
	rts

emit_primary_symbol_load:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistent
	ldx primarySymbolIndex
	jsr emit_current_load
	rts
.persistent:
	ldx primarySymbolIndex
	jsr emit_persistent_load
	rts

emit_persistent_load:
	stx emitSavedIndex
	jsr emit_txt_lda
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_c_name
	bcc .failed
	lda persistentType,x
	cmp #TYPE_CHAR
	beq .char
	jsr emit_txt_ldx
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_plus1_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.char:
	jsr emit_txt_ldx_zero
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_current_load:
	stx emitSavedIndex
	jsr emit_txt_lda
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_c_name
	bcc .failed
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .char
	jsr emit_txt_ldx
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_c_name
	bcc .failed
	jsr emit_txt_plus1_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	 rts
.char:
	jsr emit_txt_ldx_zero
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_persistent_address:
	stx emitSavedIndex
	jsr emit_txt_lda_address_low
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_nl_ldx_address_high
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_string_address:
	stx emitSavedIndex
	jsr emit_txt_lda_address_low
	bcc .failed
	ldx emitSavedIndex
	jsr emit_string_name
	bcc .failed
	jsr emit_txt_nl_ldx_address_high
	bcc .failed
	ldx emitSavedIndex
	jsr emit_string_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_store_current_value:
	stx emitSavedIndex
	jsr emit_txt_sta
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_c_name
	bcc .failed
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .char
	jsr emit_txt_stx
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_c_name
	bcc .failed
	jsr emit_txt_plus1_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.char:
	jsr emit_txt_nl
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

;;; Check local-initializer assignment compatibility before emitting the store.
;;; Integer/unsigned/char representation conversions are all bit-preserving or
;;; low-byte truncation. A char pointer accepts only a char-pointer value.
expression_value_fits_current:
	stx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR_PTR
	beq .pointerDestination
	lda exprValueType
	cmp #TYPE_CHAR_PTR
	beq .bad
	ldx emitSavedIndex
	sec
	rts
.pointerDestination:
	lda exprValueType
	cmp #TYPE_CHAR_PTR
	bne .bad
	ldx emitSavedIndex
	sec
	rts
.bad:
	ldx emitSavedIndex
	lda #EXPR_TYPE_MISMATCH
	jmp expression_fail

emit_store_spill:
	jsr emit_txt_sta
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_stx
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1_nl
	rts
.failed:
	clc
	rts

emit_unary_negate:
	lda #txtNegateEnd-txtNegate
	ldx #<txtNegate
	ldy #>txtNegate
	jmp expression_output_bytes

emit_binary_add:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_add_mid
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_add_tail
	rts
.failed:
	clc
	rts

emit_binary_subtract:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_sub_mid
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_sub_tail
	rts
.failed:
	clc
	rts

emit_binary_and:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_and_mid
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_and_tail
	rts
.failed:
	clc
	rts

emit_binary_or:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_or_mid
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_or_tail
	rts
.failed:
	clc
	rts

emit_binary_multiply:
	lda #$01
	sta expressionNeedsMultiply
	jsr emit_txt_save_right_ptr
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_mul_sta_low
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_mul_tail
	rts
.failed:
	clc
	rts

;;; A=0 left shift, A!=0 logical right shift.
emit_binary_shift:
	sta shiftRight
	jsr allocate_expression_label
	jsr emit_txt_tay
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_to_tmp_low
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_to_tmp_high
	bcc .failed
	jsr emit_txt_cpy_zero
	bcc .failed
	jsr emit_txt_beq
	bcc .failed
	jsr emit_active_done_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_active_loop_label
	bcc .failed
	lda shiftRight
	beq .left
	jsr emit_txt_lsr_tmp
	jmp .afterShift
.left:
	jsr emit_txt_asl_tmp
.afterShift:
	bcc .failed
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_loop_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_active_done_label
	bcc .failed
	jsr emit_txt_load_tmp
	rts
.failed:
	clc
	rts

emit_binary_compare:
	jsr allocate_expression_label
	jsr emit_save_right_tmp
	bcc .failed
	lda reductionOperator
	cmp #OP_EQ
	beq .eq
	cmp #OP_NE
	beq .ne
	lda reductionUnsigned
	bne .unsigned
	jsr emit_signed_relation
	bcc .failed
	jmp emit_compare_tail
.unsigned:
	jsr emit_unsigned_relation
	bcc .failed
	jmp emit_compare_tail
.eq:
	jsr emit_equality_compare
	bcc .failed
	jmp emit_compare_tail
.ne:
	jsr emit_inequality_compare
	bcc .failed
	jmp emit_compare_tail
.failed:
	clc
	rts

emit_equality_compare:
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_load_reduction_spill_high
	bcc .failed
	jsr emit_txt_cmp_tmp_high
	bcc .failed
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jsr emit_txt_nl
	rts
.failed:
	clc
	rts

emit_inequality_compare:
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_load_reduction_spill_high
	bcc .failed
	jsr emit_txt_cmp_tmp_high
	bcc .failed
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jsr emit_txt_nl
	rts
.failed:
	clc
	rts

;;; Unsigned relational compare. High bytes decide first; low bytes decide only
;;; when highs are equal. The operation selects which nearby true/false label is
;;; emitted. Comparison labels are generated inside this fixed-size snippet, so
;;; all relative branches are inherently in range.
emit_unsigned_relation:
	jsr emit_load_reduction_spill_high
	bcc .failed
	jsr emit_txt_cmp_tmp_high
	bcc .failed
	lda reductionOperator
	cmp #OP_LT
	beq .lt
	cmp #OP_LE
	beq .le
	cmp #OP_GT
	beq .gt
	jmp .ge
.lt:
	jsr emit_branch_bcc_true
	bcc .failed
	jsr emit_branch_bne_false
	bcc .failed
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_branch_bcc_true
	bcc .failed
	jmp emit_jump_false
.le:
	jsr emit_branch_bcc_true
	bcc .failed
	jsr emit_branch_bne_false
	bcc .failed
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_branch_bcc_true
	bcc .failed
	jsr emit_branch_beq_true
	bcc .failed
	jmp emit_jump_false
.gt:
	jsr emit_branch_bcc_false
	bcc .failed
	jsr emit_branch_bne_true
	bcc .failed
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_branch_bcc_false
	bcc .failed
	jsr emit_branch_beq_false
	bcc .failed
	jmp emit_jump_true
.ge:
	jsr emit_branch_bcc_false
	bcc .failed
	jsr emit_branch_bne_true
	bcc .failed
	jsr emit_load_reduction_spill_low
	bcc .failed
	jsr emit_txt_cmp_tmp
	bcc .failed
	jsr emit_branch_bcc_false
	bcc .failed
	jmp emit_jump_true
.failed:
	clc
	rts

;;; Signed relation differs from unsigned only when sign bits differ. If signs
;;; match, ordinary unsigned high/low ordering is also the signed ordering.
emit_signed_relation:
	jsr emit_load_reduction_spill_high
	bcc .failed
	jsr emit_txt_eor_tmp_high
	bcc .failed
	jsr emit_txt_bmi
	bcc .failed
	jsr emit_active_sign_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_unsigned_relation
	bcc .failed
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_done_name
	bcc .failed
	jsr emit_txt_relation_join_suffix
	bcc .failed
	jsr emit_active_sign_label
	bcc .failed
	jsr emit_load_reduction_spill_high
	bcc .failed
	lda reductionOperator
	cmp #OP_LT
	beq .negativeTrue
	cmp #OP_LE
	beq .negativeTrue
	cmp #OP_GT
	beq .negativeFalse
	cmp #OP_GE
	beq .negativeFalse
.negativeFalse:
	jsr emit_txt_bmi
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jmp emit_jump_true
.negativeTrue:
	jsr emit_txt_bmi
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jmp emit_jump_false
.failed:
	clc
	rts

;;; Canonical compare materialisation. Prelude code jumps/branches to _t/_f;
;;; both paths leave exactly int 0/1 in A/X and meet at _d.
emit_compare_tail:
	jsr emit_active_true_label
	bcc .failed
	jsr emit_txt_load_one
	bcc .failed
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_done_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_active_false_label
	bcc .failed
	jsr emit_txt_load_zero
	bcc .failed
	jsr emit_active_done_label
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Effective address / indexed load
;;; ---------------------------------------------------------------------------

emit_effective_address:
	lda effectiveElementType
	cmp #TYPE_CHAR
	beq .scaled
	lda effectiveBaseIsArray
	beq .scaled			; char * is always byte-scaled
	jsr emit_txt_scale_index_two
	bcc .failed
.scaled:
	jsr emit_txt_save_index
	bcc .failed
	lda effectiveBaseIsArray
	beq .pointerBase
	jsr emit_txt_lda_address_low
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_add_base_low_tail
	bcc .failed
	jsr emit_txt_lda_address_high
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_add_base_high_tail
	rts
.pointerBase:
	lda effectiveBaseArea
	cmp #SYMBOL_AREA_CURRENT
	bne .persistentPointer
	jsr emit_txt_lda
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_current_c_name
	bcc .failed
	jsr emit_txt_add_pointer_low_tail
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_current_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_add_base_high_tail
	rts
.persistentPointer:
	jsr emit_txt_lda
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_add_pointer_low_tail
	bcc .failed
	jsr emit_txt_lda
	bcc .failed
	ldx effectiveBaseIndex
	jsr emit_persistent_c_name
	bcc .failed
	jsr emit_txt_plus1
	bcc .failed
	jsr emit_txt_add_base_high_tail
	rts
.failed:
	clc
	rts

emit_effective_load:
	lda effectiveElementType
	cmp #TYPE_CHAR
	beq .char
	lda #txtLoadWordPtrEnd-txtLoadWordPtr
	ldx #<txtLoadWordPtr
	ldy #>txtLoadWordPtr
	jsr expression_output_bytes
	bcc .failed
	lda effectiveElementType
	sta exprValueType
	sec
	rts
.char:
	lda #txtLoadCharPtrEnd-txtLoadCharPtr
	ldx #<txtLoadCharPtr
	ldy #>txtLoadCharPtr
	jsr expression_output_bytes
	bcc .failed
	lda #TYPE_CHAR
	sta exprValueType
	sec
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Deferred string literals
;;; ---------------------------------------------------------------------------

retain_string_literal:
	ldx expressionLiteralCount
	cpx #EXPRESSION_LITERAL_COUNT_CAPACITY
	bcc .countSpace
	lda #EXPR_LITERAL_CAPACITY
	jmp expression_fail
.countSpace:
	stx literalWorkingIndex
	lda expressionLiteralPoolUsed
	sta literalCopyStart
	clc
	adc currentTokenLength
	sta literalCopyEnd
	lda expressionLiteralPoolUsed+1
	sta literalCopyStart+1
	adc #$00
	sta literalCopyEnd+1
	inc literalCopyEnd
	bne .checkPool
	inc literalCopyEnd+1
.checkPool:
	lda literalCopyEnd+1
	cmp #>EXPRESSION_LITERAL_POOL_CAPACITY
	bcc .fits
	bne .full
	lda literalCopyEnd
	cmp #<EXPRESSION_LITERAL_POOL_CAPACITY
	bcc .fits
	beq .fits
.full:
	lda #EXPR_LITERAL_CAPACITY
	jmp expression_fail
.fits:
	ldx literalWorkingIndex
	lda literalCopyStart
	sta expressionLiteralOffsetLo,x
	lda literalCopyStart+1
	sta expressionLiteralOffsetHi,x

	clc
	lda #<expressionLiteralPool
	adc literalCopyStart
	sta DECL_PTR
	lda #>expressionLiteralPool
	adc literalCopyStart+1
	sta DECL_PTR+1
	ldy #$00
	lda currentTokenLength
	sta (DECL_PTR),y
	inc DECL_PTR
	bne .copyStart
	inc DECL_PTR+1
.copyStart:
	ldy #$00
.copy:
	cpy currentTokenLength
	beq .done
	lda currentTokenText,y
	sta (DECL_PTR),y
	iny
	jmp .copy
.done:
	lda literalCopyEnd
	sta expressionLiteralPoolUsed
	lda literalCopyEnd+1
	sta expressionLiteralPoolUsed+1
	inc expressionLiteralCount
	ldx literalWorkingIndex
	sec
	rts

;;; emit_expression_literals
;;; Emit all function-body strings after executable code. Records retain only
;;; length+bytes; the generated label is the literal ordinal.
emit_expression_literals:
	lda #$00
	sta literalEmitIndex
.loop:
	lda literalEmitIndex
	cmp expressionLiteralCount
	beq .done
	tax
	jsr emit_string_label
	bcc .failed
	jsr literal_record_pointer
	bcc .failed
	ldy #$00
	lda (DECL_PTR),y
	sta literalEmitLength
	inc DECL_PTR
	bne .bytesStart
	inc DECL_PTR+1
.bytesStart:
	jsr emit_txt_byte_prefix
	bcc .failed
	lda #$00
	sta literalEmitByte
.bytes:
	lda literalEmitByte
	cmp literalEmitLength
	beq .nul
	tay
	lda (DECL_PTR),y
	jsr emit_hex_byte
	bcc .failed
	inc literalEmitByte
	lda literalEmitByte
	cmp literalEmitLength
	beq .commaBeforeNul
	jsr emit_txt_comma_dollar
	bcc .failed
	jmp .bytes
.commaBeforeNul:
	jsr emit_txt_comma_dollar
	bcc .failed
.nul:
	lda #$00
	jsr emit_hex_byte
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	inc literalEmitIndex
	jmp .loop
.done:
	sec
	rts
.failed:
	clc
	rts

literal_record_pointer:
	ldx literalEmitIndex
	lda expressionLiteralOffsetLo,x
	sta literalCopyStart
	lda expressionLiteralOffsetHi,x
	sta literalCopyStart+1
	clc
	lda #<expressionLiteralPool
	adc literalCopyStart
	sta DECL_PTR
	lda #>expressionLiteralPool
	adc literalCopyStart+1
	sta DECL_PTR+1
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Generated-name emitters
;;; ---------------------------------------------------------------------------

;;; X=persistent symbol. Emit `__c_` followed by its owned source spelling.
emit_persistent_c_name:
	stx emitSavedIndex
	jsr emit_txt_c_prefix
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_source_name
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_persistent_source_name:
	stx emitSavedIndex2
	lda persistentNameOffsetLo,x
	sta nameEmitOffset
	lda persistentNameOffsetHi,x
	sta nameEmitOffset+1
	clc
	lda #<namePool
	adc nameEmitOffset
	sta DECL_PTR
	lda #>namePool
	adc nameEmitOffset+1
	sta DECL_PTR+1
	ldy #$00
	lda (DECL_PTR),y
	sta nameEmitLength
	inc DECL_PTR
	bne .havePointer
	inc DECL_PTR+1
.havePointer:
	lda nameEmitLength
	ldx DECL_PTR
	ldy DECL_PTR+1
	jsr expression_output_bytes
	ldx emitSavedIndex2
	rts

;;; X=current-function symbol. Parameters are current indices 0..N-1, so #57
;;; can derive exactly the same callee slot name from function symbol + ordinal.
emit_current_c_name:
	stx emitSavedIndex
	jsr emit_txt_c_prefix
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	jsr emit_txt_current_suffix
	bcc .failed
	lda emitSavedIndex
	jsr emit_hex_byte
	bcc .failed
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

;;; A=spill depth.
emit_spill_c_name:
	sta emitSavedValue
	jsr emit_txt_c_prefix
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	jsr emit_txt_spill_suffix
	bcc .failed
	lda emitSavedValue
	jsr emit_hex_byte
	rts
.failed:
	clc
	rts

;;; X=literal ordinal.
emit_string_name:
	stx emitSavedIndex
	jsr emit_txt_string_prefix
	bcc .failed
	lda emitSavedIndex
	jsr emit_hex_byte
	ldx emitSavedIndex
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_string_label:
	jsr emit_string_name
	bcc .failed
	jsr emit_txt_colon_nl
	rts
.failed:
	clc
	rts

emit_spill_definition:
	jsr emit_spill_c_name
	bcc .failed
	jsr emit_txt_bss_assignment
	bcc .failed
	lda allocOffset+1
	jsr emit_hex_byte
	bcc .failed
	lda allocOffset
	jsr emit_hex_byte
	bcc .failed
	jsr emit_txt_nl
	rts
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Comparison/shift generated-label helpers
;;; ---------------------------------------------------------------------------

allocate_expression_label:
	lda expressionLabelCounter
	sta activeLabel
	lda expressionLabelCounter+1
	sta activeLabel+1
	inc expressionLabelCounter
	bne .done
	inc expressionLabelCounter+1
.done:
	rts

emit_active_label_base:
	jsr emit_txt_expression_prefix
	bcc .failed
	lda activeLabel+1
	jsr emit_hex_byte
	bcc .failed
	lda activeLabel
	jsr emit_hex_byte
	rts
.failed:
	clc
	rts

emit_active_true_name:
	jsr emit_active_label_base
	bcc .failed
	jsr emit_txt_true_suffix
	rts
.failed:
	clc
	rts
emit_active_false_name:
	jsr emit_active_label_base
	bcc .failed
	jsr emit_txt_false_suffix
	rts
.failed:
	clc
	rts
emit_active_done_name:
	jsr emit_active_label_base
	bcc .failed
	jsr emit_txt_done_suffix
	rts
.failed:
	clc
	rts
emit_active_loop_name:
	jsr emit_active_label_base
	bcc .failed
	jsr emit_txt_loop_suffix
	rts
.failed:
	clc
	rts
emit_active_sign_name:
	jsr emit_active_label_base
	bcc .failed
	jsr emit_txt_sign_suffix
	rts
.failed:
	clc
	rts

emit_active_true_label:
	jsr emit_active_true_name
	bcc .failed
	jmp emit_txt_colon_nl
.failed:
	clc
	rts
emit_active_false_label:
	jsr emit_active_false_name
	bcc .failed
	jmp emit_txt_colon_nl
.failed:
	clc
	rts
emit_active_done_label:
	jsr emit_active_done_name
	bcc .failed
	jmp emit_txt_colon_nl
.failed:
	clc
	rts
emit_active_loop_label:
	jsr emit_active_loop_name
	bcc .failed
	jmp emit_txt_colon_nl
.failed:
	clc
	rts
emit_active_sign_label:
	jsr emit_active_sign_name
	bcc .failed
	jmp emit_txt_colon_nl
.failed:
	clc
	rts

emit_branch_bcc_true:
	jsr emit_txt_bcc
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_branch_bcc_false:
	jsr emit_txt_bcc
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_branch_bne_true:
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_branch_bne_false:
	jsr emit_txt_bne
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_branch_beq_true:
	jsr emit_txt_beq
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_branch_beq_false:
	jsr emit_txt_beq
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_jump_true:
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_true_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts
emit_jump_false:
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_false_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts

emit_compare_tail:
	jsr emit_active_true_label
	bcc .failed
	jsr emit_txt_load_one
	bcc .failed
	jsr emit_txt_jmp
	bcc .failed
	jsr emit_active_done_name
	bcc .failed
	jsr emit_txt_nl
	bcc .failed
	jsr emit_active_false_label
	bcc .failed
	jsr emit_txt_load_zero
	bcc .failed
	jsr emit_active_done_label
	rts
.failed:
	clc
	rts

;;; Signed compare's same-sign path uses ordinary unsigned relation then jumps
;;; over the sign-difference block. This tiny join label is separate from _d,
;;; which belongs to the canonical 0/1 tail.
emit_txt_relation_join_suffix:
	jsr emit_txt_colon_nl
	rts

;;; ---------------------------------------------------------------------------
;;; Small dynamic emission helpers
;;; ---------------------------------------------------------------------------

emit_save_right_tmp:
	lda #txtSaveTmpEnd-txtSaveTmp
	ldx #<txtSaveTmp
	ldy #>txtSaveTmp
	jmp expression_output_bytes

emit_load_reduction_spill_low:
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jmp emit_txt_nl
.failed:
	clc
	rts

emit_load_reduction_spill_high:
	jsr emit_txt_lda
	bcc .failed
	lda reductionSpillDepth
	jsr emit_spill_c_name
	bcc .failed
	jmp emit_txt_plus1_nl
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Output primitives / hexadecimal formatting
;;; ---------------------------------------------------------------------------

expression_output_bytes:
	jsr emit_output_bytes
	bcs .ok
	lda #EXPR_EMIT_ERROR
	sta expressionError
	clc
	rts
.ok:
	sec
	rts

expression_output_byte:
	jsr emit_output_byte
	bcs .ok
	lda #EXPR_EMIT_ERROR
	sta expressionError
	clc
	rts
.ok:
	sec
	rts

emit_hex_byte:
	sta emitHexValue
	lsr
	lsr
	lsr
	lsr
	jsr emit_hex_nibble
	bcc .failed
	lda emitHexValue
	and #$0f
	jsr emit_hex_nibble
	rts
.failed:
	clc
	rts

emit_hex_nibble:
	cmp #10
	bcc .digit
	clc
	adc #'A'-10
	jmp expression_output_byte
.digit:
	clc
	adc #'0'
	jmp expression_output_byte

;;; ---------------------------------------------------------------------------
;;; Fixed output fragments. Numeric ASCII keeps this source in the simple syntax
;;; shared by vasm and the project's own assembler.
;;; ---------------------------------------------------------------------------

emit_txt_lda_imm:
	lda #txtLdaImmEnd-txtLdaImm
	ldx #<txtLdaImm
	ldy #>txtLdaImm
	jmp expression_output_bytes
emit_txt_ldx_imm:
	lda #txtLdxImmEnd-txtLdxImm
	ldx #<txtLdxImm
	ldy #>txtLdxImm
	jmp expression_output_bytes
emit_txt_lda:
	lda #txtLdaEnd-txtLda
	ldx #<txtLda
	ldy #>txtLda
	jmp expression_output_bytes
emit_txt_ldx:
	lda #txtLdxEnd-txtLdx
	ldx #<txtLdx
	ldy #>txtLdx
	jmp expression_output_bytes
emit_txt_sta:
	lda #txtStaEnd-txtSta
	ldx #<txtSta
	ldy #>txtSta
	jmp expression_output_bytes
emit_txt_stx:
	lda #txtStxEnd-txtStx
	ldx #<txtStx
	ldy #>txtStx
	jmp expression_output_bytes
emit_txt_nl:
	lda #txtNlEnd-txtNl
	ldx #<txtNl
	ldy #>txtNl
	jmp expression_output_bytes
emit_txt_plus1:
	lda #txtPlus1End-txtPlus1
	ldx #<txtPlus1
	ldy #>txtPlus1
	jmp expression_output_bytes
emit_txt_plus1_nl:
	lda #txtPlus1NlEnd-txtPlus1Nl
	ldx #<txtPlus1Nl
	ldy #>txtPlus1Nl
	jmp expression_output_bytes
emit_txt_ldx_zero:
	lda #txtLdxZeroEnd-txtLdxZero
	ldx #<txtLdxZero
	ldy #>txtLdxZero
	jmp expression_output_bytes
emit_txt_lda_address_low:
	lda #txtLdaAddressLowEnd-txtLdaAddressLow
	ldx #<txtLdaAddressLow
	ldy #>txtLdaAddressLow
	jmp expression_output_bytes
emit_txt_lda_address_high:
	lda #txtLdaAddressHighEnd-txtLdaAddressHigh
	ldx #<txtLdaAddressHigh
	ldy #>txtLdaAddressHigh
	jmp expression_output_bytes
emit_txt_nl_ldx_address_high:
	lda #txtNlLdxAddressHighEnd-txtNlLdxAddressHigh
	ldx #<txtNlLdxAddressHigh
	ldy #>txtNlLdxAddressHigh
	jmp expression_output_bytes
emit_txt_c_prefix:
	lda #txtCPrefixEnd-txtCPrefix
	ldx #<txtCPrefix
	ldy #>txtCPrefix
	jmp expression_output_bytes
emit_txt_current_suffix:
	lda #txtCurrentSuffixEnd-txtCurrentSuffix
	ldx #<txtCurrentSuffix
	ldy #>txtCurrentSuffix
	jmp expression_output_bytes
emit_txt_spill_suffix:
	lda #txtSpillSuffixEnd-txtSpillSuffix
	ldx #<txtSpillSuffix
	ldy #>txtSpillSuffix
	jmp expression_output_bytes
emit_txt_string_prefix:
	lda #txtStringPrefixEnd-txtStringPrefix
	ldx #<txtStringPrefix
	ldy #>txtStringPrefix
	jmp expression_output_bytes
emit_txt_expression_prefix:
	lda #txtExpressionPrefixEnd-txtExpressionPrefix
	ldx #<txtExpressionPrefix
	ldy #>txtExpressionPrefix
	jmp expression_output_bytes
emit_txt_true_suffix:
	lda #txtTrueSuffixEnd-txtTrueSuffix
	ldx #<txtTrueSuffix
	ldy #>txtTrueSuffix
	jmp expression_output_bytes
emit_txt_false_suffix:
	lda #txtFalseSuffixEnd-txtFalseSuffix
	ldx #<txtFalseSuffix
	ldy #>txtFalseSuffix
	jmp expression_output_bytes
emit_txt_done_suffix:
	lda #txtDoneSuffixEnd-txtDoneSuffix
	ldx #<txtDoneSuffix
	ldy #>txtDoneSuffix
	jmp expression_output_bytes
emit_txt_loop_suffix:
	lda #txtLoopSuffixEnd-txtLoopSuffix
	ldx #<txtLoopSuffix
	ldy #>txtLoopSuffix
	jmp expression_output_bytes
emit_txt_sign_suffix:
	lda #txtSignSuffixEnd-txtSignSuffix
	ldx #<txtSignSuffix
	ldy #>txtSignSuffix
	jmp expression_output_bytes
emit_txt_bss_assignment:
	lda #txtBssAssignmentEnd-txtBssAssignment
	ldx #<txtBssAssignment
	ldy #>txtBssAssignment
	jmp expression_output_bytes
emit_txt_colon_nl:
	lda #txtColonNlEnd-txtColonNl
	ldx #<txtColonNl
	ldy #>txtColonNl
	jmp expression_output_bytes
emit_txt_add_mid:
	lda #txtAddMidEnd-txtAddMid
	ldx #<txtAddMid
	ldy #>txtAddMid
	jmp expression_output_bytes
emit_txt_add_tail:
	lda #txtAddTailEnd-txtAddTail
	ldx #<txtAddTail
	ldy #>txtAddTail
	jmp expression_output_bytes
emit_txt_sub_mid:
	lda #txtSubMidEnd-txtSubMid
	ldx #<txtSubMid
	ldy #>txtSubMid
	jmp expression_output_bytes
emit_txt_sub_tail:
	lda #txtSubTailEnd-txtSubTail
	ldx #<txtSubTail
	ldy #>txtSubTail
	jmp expression_output_bytes
emit_txt_and_mid:
	lda #txtAndMidEnd-txtAndMid
	ldx #<txtAndMid
	ldy #>txtAndMid
	jmp expression_output_bytes
emit_txt_and_tail:
	lda #txtAndTailEnd-txtAndTail
	ldx #<txtAndTail
	ldy #>txtAndTail
	jmp expression_output_bytes
emit_txt_or_mid:
	lda #txtOrMidEnd-txtOrMid
	ldx #<txtOrMid
	ldy #>txtOrMid
	jmp expression_output_bytes
emit_txt_or_tail:
	lda #txtOrTailEnd-txtOrTail
	ldx #<txtOrTail
	ldy #>txtOrTail
	jmp expression_output_bytes
emit_txt_save_right_ptr:
	lda #txtSaveRightPtrEnd-txtSaveRightPtr
	ldx #<txtSaveRightPtr
	ldy #>txtSaveRightPtr
	jmp expression_output_bytes
emit_txt_mul_sta_low:
	lda #txtMulStaLowEnd-txtMulStaLow
	ldx #<txtMulStaLow
	ldy #>txtMulStaLow
	jmp expression_output_bytes
emit_txt_mul_tail:
	lda #txtMulTailEnd-txtMulTail
	ldx #<txtMulTail
	ldy #>txtMulTail
	jmp expression_output_bytes
emit_txt_tay:
	lda #txtTayEnd-txtTay
	ldx #<txtTay
	ldy #>txtTay
	jmp expression_output_bytes
emit_txt_to_tmp_low:
	lda #txtToTmpLowEnd-txtToTmpLow
	ldx #<txtToTmpLow
	ldy #>txtToTmpLow
	jmp expression_output_bytes
emit_txt_to_tmp_high:
	lda #txtToTmpHighEnd-txtToTmpHigh
	ldx #<txtToTmpHigh
	ldy #>txtToTmpHigh
	jmp expression_output_bytes
emit_txt_cpy_zero:
	lda #txtCpyZeroEnd-txtCpyZero
	ldx #<txtCpyZero
	ldy #>txtCpyZero
	jmp expression_output_bytes
emit_txt_asl_tmp:
	lda #txtAslTmpEnd-txtAslTmp
	ldx #<txtAslTmp
	ldy #>txtAslTmp
	jmp expression_output_bytes
emit_txt_lsr_tmp:
	lda #txtLsrTmpEnd-txtLsrTmp
	ldx #<txtLsrTmp
	ldy #>txtLsrTmp
	jmp expression_output_bytes
emit_txt_load_tmp:
	lda #txtLoadTmpEnd-txtLoadTmp
	ldx #<txtLoadTmp
	ldy #>txtLoadTmp
	jmp expression_output_bytes
emit_txt_cmp_tmp:
	lda #txtCmpTmpEnd-txtCmpTmp
	ldx #<txtCmpTmp
	ldy #>txtCmpTmp
	jmp expression_output_bytes
emit_txt_cmp_tmp_high:
	lda #txtCmpTmpHighEnd-txtCmpTmpHigh
	ldx #<txtCmpTmpHigh
	ldy #>txtCmpTmpHigh
	jmp expression_output_bytes
emit_txt_eor_tmp_high:
	lda #txtEorTmpHighEnd-txtEorTmpHigh
	ldx #<txtEorTmpHigh
	ldy #>txtEorTmpHigh
	jmp expression_output_bytes
emit_txt_beq:
	lda #txtBeqEnd-txtBeq
	ldx #<txtBeq
	ldy #>txtBeq
	jmp expression_output_bytes
emit_txt_bne:
	lda #txtBneEnd-txtBne
	ldx #<txtBne
	ldy #>txtBne
	jmp expression_output_bytes
emit_txt_bcc:
	lda #txtBccEnd-txtBcc
	ldx #<txtBcc
	ldy #>txtBcc
	jmp expression_output_bytes
emit_txt_bmi:
	lda #txtBmiEnd-txtBmi
	ldx #<txtBmi
	ldy #>txtBmi
	jmp expression_output_bytes
emit_txt_jmp:
	lda #txtJmpEnd-txtJmp
	ldx #<txtJmp
	ldy #>txtJmp
	jmp expression_output_bytes
emit_txt_load_one:
	lda #txtLoadOneEnd-txtLoadOne
	ldx #<txtLoadOne
	ldy #>txtLoadOne
	jmp expression_output_bytes
emit_txt_load_zero:
	lda #txtLoadZeroEnd-txtLoadZero
	ldx #<txtLoadZero
	ldy #>txtLoadZero
	jmp expression_output_bytes
emit_txt_scale_index_two:
	lda #txtScaleIndexTwoEnd-txtScaleIndexTwo
	ldx #<txtScaleIndexTwo
	ldy #>txtScaleIndexTwo
	jmp expression_output_bytes
emit_txt_save_index:
	lda #txtSaveIndexEnd-txtSaveIndex
	ldx #<txtSaveIndex
	ldy #>txtSaveIndex
	jmp expression_output_bytes
emit_txt_add_base_low_tail:
	lda #txtAddBaseLowTailEnd-txtAddBaseLowTail
	ldx #<txtAddBaseLowTail
	ldy #>txtAddBaseLowTail
	jmp expression_output_bytes
emit_txt_add_pointer_low_tail:
	lda #txtAddPointerLowTailEnd-txtAddPointerLowTail
	ldx #<txtAddPointerLowTail
	ldy #>txtAddPointerLowTail
	jmp expression_output_bytes
emit_txt_add_base_high_tail:
	lda #txtAddBaseHighTailEnd-txtAddBaseHighTail
	ldx #<txtAddBaseHighTail
	ldy #>txtAddBaseHighTail
	jmp expression_output_bytes
emit_txt_byte_prefix:
	lda #txtBytePrefixEnd-txtBytePrefix
	ldx #<txtBytePrefix
	ldy #>txtBytePrefix
	jmp expression_output_bytes
emit_txt_comma_dollar:
	lda #txtCommaDollarEnd-txtCommaDollar
	ldx #<txtCommaDollar
	ldy #>txtCommaDollar
	jmp expression_output_bytes

;;; ---------------------------------------------------------------------------
;;; Fixed text bytes
;;; ---------------------------------------------------------------------------

txtLdaImm:	byte 32,32,32,32,108,100,97,32,35,36
txtLdaImmEnd:
txtLdxImm:	byte 10,32,32,32,32,108,100,120,32,35,36
txtLdxImmEnd:
txtLda:		byte 32,32,32,32,108,100,97,32
txtLdaEnd:
txtLdx:		byte 10,32,32,32,32,108,100,120,32
txtLdxEnd:
txtSta:		byte 32,32,32,32,115,116,97,32
txtStaEnd:
txtStx:		byte 10,32,32,32,32,115,116,120,32
txtStxEnd:
txtNl:		byte 10
txtNlEnd:
txtPlus1:	byte 43,49
txtPlus1End:
txtPlus1Nl:	byte 43,49,10
txtPlus1NlEnd:
txtLdxZero:	byte 10,32,32,32,32,108,100,120,32,35,36,48,48,10
txtLdxZeroEnd:
txtLdaAddressLow:	byte 32,32,32,32,108,100,97,32,35,60
txtLdaAddressLowEnd:
txtLdaAddressHigh:	byte 32,32,32,32,108,100,97,32,35,62
txtLdaAddressHighEnd:
txtNlLdxAddressHigh:	byte 10,32,32,32,32,108,100,120,32,35,62
txtNlLdxAddressHighEnd:
txtCPrefix:	byte 95,95,99,95
txtCPrefixEnd:
txtCurrentSuffix:	byte 95,95,118
txtCurrentSuffixEnd:
txtSpillSuffix:	byte 95,95,115
txtSpillSuffixEnd:
txtStringPrefix:	byte 95,95,110,99,95,115,116,114
txtStringPrefixEnd:
txtExpressionPrefix:	byte 95,95,110,99,95,101
txtExpressionPrefixEnd:
txtTrueSuffix:	byte 95,116
txtTrueSuffixEnd:
txtFalseSuffix:	byte 95,102
txtFalseSuffixEnd:
txtDoneSuffix:	byte 95,100
txtDoneSuffixEnd:
txtLoopSuffix:	byte 95,108
txtLoopSuffixEnd:
txtSignSuffix:	byte 95,115,105,103,110
txtSignSuffixEnd:
txtBssAssignment:	byte 32,61,32,78,67,95,66,83,83,43,36
txtBssAssignmentEnd:
txtColonNl:	byte 58,10
txtColonNlEnd:
txtSaveTmp:	byte 32,32,32,32,115,116,97,32,78,67,95,84,77,80,10,32,32,32,32,115,116,120,32,78,67,95,84,77,80,43,49,10
txtSaveTmpEnd:
txtNegate:	byte 32,32,32,32,101,111,114,32,35,36,102,102,10,32,32,32,32,99,108,99,10,32,32,32,32,97,100,99,32,35,36,48,49,10,32,32,32,32,116,97,121,10,32,32,32,32,116,120,97,10,32,32,32,32,101,111,114,32,35,36,102,102,10,32,32,32,32,97,100,99,32,35,36,48,48,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtNegateEnd:
txtAddMid:	byte 32,32,32,32,99,108,99,10,32,32,32,32,97,100,99,32,78,67,95,84,77,80,10,32,32,32,32,116,97,121,10,32,32,32,32,108,100,97,32
txtAddMidEnd:
txtAddTail:	byte 10,32,32,32,32,97,100,99,32,78,67,95,84,77,80,43,49,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtAddTailEnd:
txtSubMid:	byte 32,32,32,32,115,101,99,10,32,32,32,32,115,98,99,32,78,67,95,84,77,80,10,32,32,32,32,116,97,121,10,32,32,32,32,108,100,97,32
txtSubMidEnd:
txtSubTail:	byte 10,32,32,32,32,115,98,99,32,78,67,95,84,77,80,43,49,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtSubTailEnd:
txtAndMid:	byte 32,32,32,32,97,110,100,32,78,67,95,84,77,80,10,32,32,32,32,116,97,121,10,32,32,32,32,108,100,97,32
txtAndMidEnd:
txtAndTail:	byte 10,32,32,32,32,97,110,100,32,78,67,95,84,77,80,43,49,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtAndTailEnd:
txtOrMid:	byte 32,32,32,32,111,114,97,32,78,67,95,84,77,80,10,32,32,32,32,116,97,121,10,32,32,32,32,108,100,97,32
txtOrMidEnd:
txtOrTail:	byte 10,32,32,32,32,111,114,97,32,78,67,95,84,77,80,43,49,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtOrTailEnd:
txtSaveRightPtr:	byte 32,32,32,32,115,116,97,32,78,67,95,80,84,82,10,32,32,32,32,115,116,120,32,78,67,95,80,84,82,43,49,10
txtSaveRightPtrEnd:
txtMulStaLow:	byte 10,32,32,32,32,115,116,97,32,78,67,95,84,77,80,10,32,32,32,32,108,100,97,32
txtMulStaLowEnd:
txtMulTail:	byte 10,32,32,32,32,115,116,97,32,78,67,95,84,77,80,43,49,10,32,32,32,32,108,100,97,32,78,67,95,80,84,82,10,32,32,32,32,108,100,120,32,78,67,95,80,84,82,43,49,10,32,32,32,32,106,115,114,32,95,95,110,99,95,109,117,108,49,54,10
txtMulTailEnd:
txtTay:	byte 32,32,32,32,116,97,121,10
txtTayEnd:
txtToTmpLow:	byte 10,32,32,32,32,115,116,97,32,78,67,95,84,77,80,10
txtToTmpLowEnd:
txtToTmpHigh:	byte 10,32,32,32,32,115,116,97,32,78,67,95,84,77,80,43,49,10
txtToTmpHighEnd:
txtCpyZero:	byte 32,32,32,32,99,112,121,32,35,36,48,48,10
txtCpyZeroEnd:
txtAslTmp:	byte 32,32,32,32,97,115,108,32,78,67,95,84,77,80,10,32,32,32,32,114,111,108,32,78,67,95,84,77,80,43,49,10,32,32,32,32,100,101,121,10
txtAslTmpEnd:
txtLsrTmp:	byte 32,32,32,32,108,115,114,32,78,67,95,84,77,80,43,49,10,32,32,32,32,114,111,114,32,78,67,95,84,77,80,10,32,32,32,32,100,101,121,10
txtLsrTmpEnd:
txtLoadTmp:	byte 32,32,32,32,108,100,97,32,78,67,95,84,77,80,10,32,32,32,32,108,100,120,32,78,67,95,84,77,80,43,49,10
txtLoadTmpEnd:
txtCmpTmp:	byte 10,32,32,32,32,99,109,112,32,78,67,95,84,77,80,10
txtCmpTmpEnd:
txtCmpTmpHigh:	byte 10,32,32,32,32,99,109,112,32,78,67,95,84,77,80,43,49,10
txtCmpTmpHighEnd:
txtEorTmpHigh:	byte 32,32,32,32,101,111,114,32,78,67,95,84,77,80,43,49,10
txtEorTmpHighEnd:
txtBeq:	byte 32,32,32,32,98,101,113,32
txtBeqEnd:
txtBne:	byte 32,32,32,32,98,110,101,32
txtBneEnd:
txtBcc:	byte 32,32,32,32,98,99,99,32
txtBccEnd:
txtBmi:	byte 32,32,32,32,98,109,105,32
txtBmiEnd:
txtJmp:	byte 32,32,32,32,106,109,112,32
txtJmpEnd:
txtLoadOne:	byte 32,32,32,32,108,100,97,32,35,36,48,49,10,32,32,32,32,108,100,120,32,35,36,48,48,10
txtLoadOneEnd:
txtLoadZero:	byte 32,32,32,32,108,100,97,32,35,36,48,48,10,32,32,32,32,108,100,120,32,35,36,48,48,10
txtLoadZeroEnd:
txtScaleIndexTwo:	byte 32,32,32,32,97,115,108,10,32,32,32,32,116,97,121,10,32,32,32,32,116,120,97,10,32,32,32,32,114,111,108,10,32,32,32,32,116,97,120,10,32,32,32,32,116,121,97,10
txtScaleIndexTwoEnd:
txtSaveIndex:	byte 32,32,32,32,115,116,97,32,78,67,95,84,77,80,10,32,32,32,32,115,116,120,32,78,67,95,84,77,80,43,49,10
txtSaveIndexEnd:
txtAddBaseLowTail:	byte 10,32,32,32,32,99,108,99,10,32,32,32,32,97,100,99,32,78,67,95,84,77,80,10,32,32,32,32,115,116,97,32,78,67,95,80,84,82,10
txtAddBaseLowTailEnd:
txtAddPointerLowTail:	byte 10,32,32,32,32,99,108,99,10,32,32,32,32,97,100,99,32,78,67,95,84,77,80,10,32,32,32,32,115,116,97,32,78,67,95,80,84,82,10
txtAddPointerLowTailEnd:
txtAddBaseHighTail:	byte 10,32,32,32,32,97,100,99,32,78,67,95,84,77,80,43,49,10,32,32,32,32,115,116,97,32,78,67,95,80,84,82,43,49,10
txtAddBaseHighTailEnd:
txtBytePrefix:	byte 32,32,32,32,98,121,116,101,32,36
txtBytePrefixEnd:
txtCommaDollar:	byte 44,36
txtCommaDollarEnd:

;;; ---------------------------------------------------------------------------
;;; Compiler state. No entry here is a runtime C value.
;;; ---------------------------------------------------------------------------

expressionError:	byte EXPR_OK
expressionExpectOperand:	byte 0
expressionDone:		byte 0
exprValueType:		byte TYPE_INT
operatorStackCount:	byte 0
activeSpillDepth:	byte 0
expressionSpillAllocated:	byte 0
expressionLabelCounter:	word 0
activeLabel:		word 0
expressionNeedsMultiply:	byte 0

incomingOperator:	byte 0
incomingPrecedence:	byte 0
reductionOperator:	byte 0
reductionLeftType:	byte 0
reductionRightType:	byte 0
reductionResultType:	byte 0
reductionCombinedType:	byte 0
reductionUnsigned:	byte 0
reductionSpillDepth:	byte 0
normalizedLeftType:	byte 0
normalizedRightType:	byte 0
shiftRight:		byte 0

primarySymbolIndex:	byte 0
primarySymbolArea:	byte 0
primarySymbolType:	byte 0
primarySymbolKind:	byte 0

effectiveBaseArea:	byte 0
effectiveBaseIndex:	byte 0
effectiveBaseIsArray:	byte 0
effectiveElementType:	byte TYPE_CHAR

emitValueLo:		byte 0
emitValueHi:		byte 0
emitSavedIndex:	byte 0
emitSavedIndex2:	byte 0
emitSavedValue:	byte 0
emitHexValue:		byte 0
nameEmitOffset:	word 0
nameEmitLength:	byte 0

literalWorkingIndex:	byte 0
literalCopyStart:	word 0
literalCopyEnd:	word 0
literalEmitIndex:	byte 0
literalEmitLength:	byte 0
literalEmitByte:	byte 0

operatorStackOp:	ds EXPRESSION_STACK_CAPACITY
operatorStackType:	ds EXPRESSION_STACK_CAPACITY
operatorStackValue:	ds EXPRESSION_STACK_CAPACITY
operatorStackArea:	ds EXPRESSION_STACK_CAPACITY

expressionLiteralCount:	byte 0
expressionLiteralPoolUsed:	word 0
expressionLiteralOffsetLo:	ds EXPRESSION_LITERAL_COUNT_CAPACITY
expressionLiteralOffsetHi:	ds EXPRESSION_LITERAL_COUNT_CAPACITY
expressionLiteralPool:	ds EXPRESSION_LITERAL_POOL_CAPACITY
