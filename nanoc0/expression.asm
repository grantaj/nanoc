;;; expression.asm
;;;
;;; Nano C Phase 1 expression parser and direct `ass` code generator.
;;;
;;; This is intentionally one small explicit machine rather than recursive
;;; descent. The current value is always the value the generated program will
;;; have in A/X. Binary left operands are emitted to fixed per-function spill
;;; slots before later source is consumed. The compiler retains no expression
;;; tree, RPN stream or runtime value stack.
;;;
;;; emit.asm streams generated source directly when its output flag is enabled.
;;; Function calls are the one deliberately unfinished primary:
;;; expression_call_primary receives X=known persistent function index with
;;; currentTokenKind='(' and will become #57's non-recursive pending-call state
;;; machine. The #55 stub fails explicitly rather than pretending to compile a
;;; call with semantics that would later have to be replaced.

	include "emit.asm"

EXPR_OK                    = 0
EXPR_EXPECTED_VALUE        = 1
EXPR_STACK_OVERFLOW        = 2
EXPR_UNMATCHED_DELIMITER   = 3
EXPR_UNDECLARED            = 4
EXPR_BAD_PRIMARY           = 5
EXPR_BAD_TYPE              = 6
EXPR_BSS_OVERFLOW          = 7
EXPR_EMIT_ERROR            = 8
EXPR_LITERAL_COUNT_OVERFLOW = 9
EXPR_LITERAL_POOL_OVERFLOW  = 10
EXPR_CALL_UNAVAILABLE       = 11

EXPR_STACK_CAPACITY   = 16
EXPR_LITERAL_CAPACITY = 16
EXPR_LITERAL_BYTES    = 512

OP_GROUP = 1
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

PREC_MUL   = 70
PREC_ADD   = 60
PREC_SHIFT = 50
PREC_REL   = 40
PREC_EQ    = 30
PREC_AND   = 20
PREC_OR    = 10

;;; reset_expression_translation_state
;;; Literal bytes and generated labels belong to one translation unit.
reset_expression_translation_state:
	lda #$00
	sta literalCount
	sta literalBytesUsed
	sta literalBytesUsed+1
	jsr reset_generated_labels
	jmp reset_expression_function_state

;;; reset_expression_function_state
;;; Spill labels are reused by depth inside each function. Previously allocated
;;; BSS itself remains allocated, but a new function owns a new label namespace.
reset_expression_function_state:
	lda #$00
	sta operatorCount
	sta expressionSpillDepth
	sta spillAllocatedCount
	sta expressionError
	rts

;;; parse_expression
;;; Compile one expression beginning at currentToken. The first token that is
;;; not part of the expression is left current for the caller (typically ';',
;;; ',', ')' or ']'). Carry set means the generated value is in target A/X and
;;; expressionValueType describes it.
parse_expression:
	lda #EXPR_OK
	sta expressionError
	lda #$00
	sta operatorCount
	sta expressionSpillDepth
	lda #$01
	sta expressionNeedValue

.value:
	lda currentTokenKind
	cmp #'-'
	beq .unaryMinus
	cmp #'('
	beq .openGroup
	jsr parse_expression_primary
	bcc .failed
	jsr reduce_unary_operators
	bcc .failed
	jsr handle_postfix_index
	bcc .failed
	lda expressionNeedValue
	bne .value
	jmp .operator

.unaryMinus:
	lda #OP_NEG
	jsr push_simple_operator
	bcc .failed
	jsr parser_next
	bcc .scannerFail
	jmp .value

.openGroup:
	lda #OP_GROUP
	jsr push_simple_operator
	bcc .failed
	jsr parser_next
	bcc .scannerFail
	jmp .value

.operator:
	lda currentTokenKind
	cmp #')'
	beq .closeGroup
	cmp #']'
	beq .closeIndex

	jsr binary_operator_for_token
	bcc .finish
	sta pendingOperator
	sty pendingPrecedence
	jsr reduce_for_precedence
	bcc .failed
	jsr spill_current_value
	bcc .failed
	jsr push_pending_binary
	bcc .failed
	jsr parser_next
	bcc .scannerFail
	lda #$01
	sta expressionNeedValue
	jmp .value

.closeGroup:
	lda #OP_GROUP
	jsr reduce_to_marker
	bcc .finish
	jsr pop_group_marker
	bcc .failed
	jsr parser_next
	bcc .scannerFail
	jsr reduce_unary_operators
	bcc .failed
	jsr handle_postfix_index
	bcc .failed
	lda expressionNeedValue
	bne .value
	jmp .operator

.closeIndex:
	lda #OP_INDEX
	jsr reduce_to_marker
	bcc .finish
	jsr pop_index_marker
	bcc .failed
	jsr parser_next
	bcc .scannerFail
	jsr reduce_unary_operators
	bcc .failed
	jsr handle_postfix_index
	bcc .failed
	lda expressionNeedValue
	bne .value
	jmp .operator

.finish:
	lda expressionNeedValue
	beq .haveValue
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail
.haveValue:
	jsr reduce_all_operators
	bcc .failed
	lda operatorCount
	beq .ok
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.ok:
	sec
	rts
.scannerFail:
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.failed:
	clc
	rts

expression_fail:
	sta expressionError
	clc
	rts

;;; parse_expression_primary
;;; Emit one primary and advance currentToken beyond it. The routine records
;;; whether the resulting address may be followed by indexing.
parse_expression_primary:
	lda #$00
	sta expressionIndexable
	sta expressionArrayOnly
	lda currentTokenKind
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

.integer:
	lda currentTokenValue
	sta expressionLiteralValue
	lda currentTokenValue+1
	sta expressionLiteralValue+1
	lda currentTokenType
	cmp #TOKEN_TYPE_UNSIGNED
	beq .integerUnsigned
	lda #TYPE_INT
	jmp .integerTypeDone
.integerUnsigned:
	lda #TYPE_UNSIGNED
.integerTypeDone:
	sta expressionValueType
	jsr emit_load_literal
	bcc .emitFail
	jsr parser_next
	bcc .scanFail
	lda #$00
	sta expressionNeedValue
	sec
	rts

.character:
	lda currentTokenValue
	sta expressionLiteralValue
	lda #$00
	sta expressionLiteralValue+1
	lda #TYPE_INT
	sta expressionValueType
	jsr emit_load_literal
	bcc .emitFail
	jsr parser_next
	bcc .scanFail
	lda #$00
	sta expressionNeedValue
	sec
	rts

.string:
	jsr capture_string_literal
	bcc .failed
	jsr emit_load_literal_address
	bcc .emitFail
	lda #TYPE_CHAR_PTR
	sta expressionValueType
	lda #$01
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
	jsr parser_next
	bcc .scanFail
	lda #$00
	sta expressionNeedValue
	sec
	rts

.identifier:
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
	jmp .advanceName
.current:
	lda #SYMBOL_GLOBAL
	sta primarySymbolKind
	ldx primarySymbolIndex
	lda currentType,x
	sta primarySymbolType
.advanceName:
	jsr parser_next
	bcc .scanFail

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
	lda #$01
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
.loadScalar:
	jsr emit_load_primary_scalar
	bcc .emitFail
	lda #$00
	sta expressionNeedValue
	sec
	rts

.array:
	lda primarySymbolType
	sta expressionElementType
	lda #TYPE_CHAR_PTR
	sta expressionValueType
	lda #$01
	sta expressionIndexable
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq .arrayCanDecay
	lda #$01
	sta expressionArrayOnly
.arrayCanDecay:
	jsr emit_load_primary_address
	bcc .emitFail
	lda #$00
	sta expressionNeedValue
	sec
	rts

.function:
	lda currentTokenKind
	cmp #'('
	beq .call
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.call:
	ldx primarySymbolIndex
	jsr expression_call_primary
	bcc .failed
	lda #$00
	sta expressionNeedValue
	sec
	rts

.emitFail:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.scanFail:
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.failed:
	clc
	rts

;;; #55 intentionally exposes the final call-primary shape but does not consume
;;; call syntax. #57 replaces this routine with the pending-call stack without
;;; changing the expression parser above.
expression_call_primary:
	lda #EXPR_CALL_UNAVAILABLE
	jmp expression_fail

;;; Postfix indexing is represented by a marker on the same explicit operator
;;; stack. The base address is spilled before the index expression begins.
handle_postfix_index:
	lda currentTokenKind
	cmp #'['
	beq .index
	lda expressionArrayOnly
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
	jsr spill_current_value
	bcc .failed
	ldx operatorCount
	cpx #EXPR_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	lda #OP_INDEX
	sta operatorKind,x
	lda expressionSpillDepth
	sec
	sbc #$01
	sta operatorSpill,x
	lda expressionElementType
	sta operatorType,x
	inc operatorCount
	jsr parser_next
	bcc .scanFail
	lda #$01
	sta expressionNeedValue
	lda #$00
	sta expressionIndexable
	sta expressionArrayOnly
	sec
	rts
.scanFail:
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.failed:
	clc
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
	inc operatorCount
	sec
	rts

;;; spill_current_value
;;; Save target A/X into the reusable slot for expressionSpillDepth. Allocate
;;; that static word only the first time this function reaches the depth.
spill_current_value:
	lda expressionSpillDepth
	cmp #EXPR_STACK_CAPACITY
	bcc .depthOk
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.depthOk:
	cmp spillAllocatedCount
	bcc .allocated
	lda #$02
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcs .bssOk
	lda #EXPR_BSS_OVERFLOW
	jmp expression_fail
.bssOk:
	lda expressionSpillDepth
	jsr emit_spill_definition
	bcc .emitFail
	inc spillAllocatedCount
.allocated:
	lda expressionSpillDepth
	jsr emit_store_spill
	bcc .emitFail
	inc expressionSpillDepth
	sec
	rts
.emitFail:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

push_pending_binary:
	ldx operatorCount
	cpx #EXPR_STACK_CAPACITY
	bcc .space
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.space:
	lda pendingOperator
	sta operatorKind,x
	lda expressionSpillDepth
	sec
	sbc #$01
	sta operatorSpill,x
	lda expressionValueType
	sta operatorType,x
	inc operatorCount
	sec
	rts

;;; reduce_unary_operators
;;; Unary minus is right-associative simply because consecutive '-' markers stay
;;; stacked until a primary has been emitted, then reduce from the top.
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
	bcc .failed
	dec operatorCount
	jmp .loop
.done:
	sec
.failed:
	rts

reduce_unary_minus:
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	bne .integer
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.integer:
	jsr emit_unary_minus
	bcc .emitFail
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
.emitFail:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

;;; binary_operator_for_token
;;; Carry set: A=OP_*, Y=precedence. Carry clear means expression terminator.
binary_operator_for_token:
	lda currentTokenKind
	cmp #'*'
	beq .mul
	cmp #'+'
	beq .add
	cmp #'-'
	beq .sub
	cmp #TOKEN_SHL
	beq .shl
	cmp #TOKEN_SHR
	beq .shr
	cmp #'<'
	beq .lt
	cmp #TOKEN_LE
	beq .le
	cmp #'>'
	beq .gt
	cmp #TOKEN_GE
	beq .ge
	cmp #TOKEN_EQ
	beq .eq
	cmp #TOKEN_NE
	beq .ne
	cmp #'&'
	beq .and
	cmp #'|'
	beq .or
	clc
	rts
.mul:	lda #OP_MUL
	ldy #PREC_MUL
	sec
	rts
.add:	lda #OP_ADD
	ldy #PREC_ADD
	sec
	rts
.sub:	lda #OP_SUB
	ldy #PREC_ADD
	sec
	rts
.shl:	lda #OP_SHL
	ldy #PREC_SHIFT
	sec
	rts
.shr:	lda #OP_SHR
	ldy #PREC_SHIFT
	sec
	rts
.lt:	lda #OP_LT
	ldy #PREC_REL
	sec
	rts
.le:	lda #OP_LE
	ldy #PREC_REL
	sec
	rts
.gt:	lda #OP_GT
	ldy #PREC_REL
	sec
	rts
.ge:	lda #OP_GE
	ldy #PREC_REL
	sec
	rts
.eq:	lda #OP_EQ
	ldy #PREC_EQ
	sec
	rts
.ne:	lda #OP_NE
	ldy #PREC_EQ
	sec
	rts
.and:	lda #OP_AND
	ldy #PREC_AND
	sec
	rts
.or:	lda #OP_OR
	ldy #PREC_OR
	sec
	rts

operator_precedence:
	cmp #OP_MUL
	beq .mul
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .add
	cmp #OP_SHL
	beq .shift
	cmp #OP_SHR
	beq .shift
	cmp #OP_LT
	bcc .none
	cmp #OP_GE+1
	bcc .rel
	cmp #OP_EQ
	beq .eq
	cmp #OP_NE
	beq .eq
	cmp #OP_AND
	beq .and
	cmp #OP_OR
	beq .or
.none:	ldy #$00
	rts
.mul:	ldy #PREC_MUL
	rts
.add:	ldy #PREC_ADD
	rts
.shift:	ldy #PREC_SHIFT
	rts
.rel:	ldy #PREC_REL
	rts
.eq:	ldy #PREC_EQ
	rts
.and:	ldy #PREC_AND
	rts
.or:	ldy #PREC_OR
	rts

;;; reduce_for_precedence
;;; All binary Phase 1 operators are left associative.
reduce_for_precedence:
.loop:
	lda operatorCount
	beq .done
	tax
	dex
	lda operatorKind,x
	cmp #OP_GROUP
	beq .done
	cmp #OP_INDEX
	beq .done
	cmp #OP_NEG
	beq .unary
	jsr operator_precedence
	cpy pendingPrecedence
	bcc .done
	jsr reduce_top_binary
	bcc .failed
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcc .failed
	jmp .loop
.done:
	sec
.failed:
	rts

;;; reduce_to_marker
;;; A=marker kind. Reduce binary operators above it. Carry clear means no such
;;; marker belongs to this delimiter, so the delimiter is for the caller.
reduce_to_marker:
	sta wantedMarker
.loop:
	lda operatorCount
	beq .notFound
	tax
	dex
	lda operatorKind,x
	cmp wantedMarker
	beq .found
	cmp #OP_GROUP
	beq .mismatch
	cmp #OP_INDEX
	beq .mismatch
	cmp #OP_NEG
	beq .unary
	jsr reduce_top_binary
	bcc .failed
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcc .failed
	jmp .loop
.mismatch:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.found:
	sec
	rts
.notFound:
	clc
	rts
.failed:
	clc
	rts

pop_group_marker:
	lda operatorCount
	beq .bad
	dec operatorCount
	sec
	rts
.bad:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail

pop_index_marker:
	lda operatorCount
	beq .bad
	tax
	dex
	lda operatorKind,x
	cmp #OP_INDEX
	bne .bad
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	beq .badType
	lda operatorSpill,x
	sta reduceSpill
	lda operatorType,x
	sta reduceLeftType
	dec operatorCount
	dec expressionSpillDepth
	jsr emit_index_load
	bcc .emitFail
	lda reduceLeftType
	sta expressionValueType
	lda #$00
	sta expressionArrayOnly
	sta expressionIndexable
	sec
	rts
.badType:
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.bad:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.emitFail:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

reduce_all_operators:
.loop:
	lda operatorCount
	beq .done
	tax
	dex
	lda operatorKind,x
	cmp #OP_GROUP
	beq .marker
	cmp #OP_INDEX
	beq .marker
	cmp #OP_NEG
	beq .unary
	jsr reduce_top_binary
	bcc .failed
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcc .failed
	jmp .loop
.marker:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.done:
	sec
.failed:
	rts

reduce_top_binary:
	lda operatorCount
	beq .bad
	tax
	dex
	lda operatorKind,x
	sta reduceOperator
	lda operatorSpill,x
	sta reduceSpill
	lda operatorType,x
	sta reduceLeftType
	lda expressionValueType
	sta reduceRightType

	jsr validate_binary_types
	bcc .failed
	jsr emit_binary_reduction
	bcc .emitFail
	dec operatorCount
	dec expressionSpillDepth
	lda reduceResultType
	sta expressionValueType
	lda #$00
	sta expressionArrayOnly
	sta expressionIndexable
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	bne .done
	lda #$01
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
.done:
	sec
	rts
.bad:
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail
.emitFail:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.failed:
	clc
	rts

;;; validate_binary_types
;;; Work only with the four Phase 1 scalar types. char promotes to int.
validate_binary_types:
	lda reduceOperator
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	beq .integerOnly
	cmp #OP_MUL
	beq .integerOnly
	cmp #OP_SHL
	beq .shift
	cmp #OP_SHR
	beq .shift
	cmp #OP_AND
	beq .integerOnly
	cmp #OP_OR
	beq .integerOnly
	cmp #OP_LT
	bcc .bad
	cmp #OP_NE+1
	bcc .comparison
	jmp .bad

.add:
	lda reduceLeftType
	cmp #TYPE_CHAR_PTR
	bne .integerOnly
	lda reduceRightType
	jsr type_is_integer
	bcc .bad
	lda #TYPE_CHAR_PTR
	sta reduceResultType
	sec
	rts

.integerOnly:
	lda reduceLeftType
	jsr type_is_integer
	bcc .bad
	lda reduceRightType
	jsr type_is_integer
	bcc .bad
	jsr combined_integer_type
	sta reduceResultType
	sec
	rts

.shift:
	lda reduceLeftType
	jsr type_is_integer
	bcc .bad
	lda reduceRightType
	jsr type_is_integer
	bcc .bad
	lda reduceLeftType
	cmp #TYPE_UNSIGNED
	beq .shiftUnsigned
	lda #TYPE_INT
	jmp .shiftStore
.shiftUnsigned:
	lda #TYPE_UNSIGNED
.shiftStore:
	sta reduceResultType
	sec
	rts

.comparison:
	lda reduceLeftType
	jsr type_is_integer
	bcc .bad
	lda reduceRightType
	jsr type_is_integer
	bcc .bad
	lda #TYPE_INT
	sta reduceResultType
	sec
	rts
.bad:
	lda #EXPR_BAD_TYPE
	jmp expression_fail

type_is_integer:
	cmp #TYPE_CHAR
	beq .yes
	cmp #TYPE_INT
	beq .yes
	cmp #TYPE_UNSIGNED
	beq .yes
	clc
	rts
.yes:
	sec
	rts

combined_integer_type:
	lda reduceLeftType
	cmp #TYPE_UNSIGNED
	beq .unsigned
	lda reduceRightType
	cmp #TYPE_UNSIGNED
	beq .unsigned
	lda #TYPE_INT
	rts
.unsigned:
	lda #TYPE_UNSIGNED
	rts

;;; ---------------------------------------------------------------------------
;;; Deferred string literals
;;; ---------------------------------------------------------------------------

capture_string_literal:
	lda literalCount
	cmp #EXPR_LITERAL_CAPACITY
	bcc .countOk
	lda #EXPR_LITERAL_COUNT_OVERFLOW
	jmp expression_fail
.countOk:
	sta currentLiteralIndex
	asl
	tax
	lda literalBytesUsed
	sta literalOffset,x
	lda literalBytesUsed+1
	sta literalOffset+1,x
	lda currentTokenLength
	sta literalLength,x
	lda #$00
	sta literalLength+1,x

	clc
	lda literalBytesUsed
	adc currentTokenLength
	sta literalNewEnd
	lda literalBytesUsed+1
	adc #$00
	sta literalNewEnd+1
	inc literalNewEnd
	bne .capacity
	inc literalNewEnd+1
.capacity:
	lda literalNewEnd+1
	cmp #>EXPR_LITERAL_BYTES
	bcc .fits
	bne .tooMany
	lda literalNewEnd
	cmp #<EXPR_LITERAL_BYTES
	bcc .fits
	beq .fits
.tooMany:
	lda #EXPR_LITERAL_POOL_OVERFLOW
	jmp expression_fail
.fits:
	clc
	lda #<literalBytes
	adc literalBytesUsed
	sta EMIT_PTR
	lda #>literalBytes
	adc literalBytesUsed+1
	sta EMIT_PTR+1
	ldy #$00
.copy:
	cpy currentTokenLength
	beq .nul
	lda currentTokenText,y
	sta (EMIT_PTR),y
	iny
	jmp .copy
.nul:
	lda #$00
	sta (EMIT_PTR),y
	lda literalNewEnd
	sta literalBytesUsed
	lda literalNewEnd+1
	sta literalBytesUsed+1
	inc literalCount
	sec
	rts

;;; emit_deferred_literals
;;; Called after all function code. Each literal is a label plus raw byte list.
emit_deferred_literals:
	lda #$00
	sta literalEmitIndex
.loop:
	lda literalEmitIndex
	cmp literalCount
	beq .done
	jsr emit_one_literal
	bcc .failed
	inc literalEmitIndex
	jmp .loop
.done:
	sec
.failed:
	rts

emit_one_literal:
	lda literalEmitIndex
	jsr emit_literal_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprBytePrefixEnd-exprBytePrefix
	ldx #<exprBytePrefix
	ldy #>exprBytePrefix
	jsr emit_text
	bcc .failed

	lda literalEmitIndex
	asl
	tax
	lda literalOffset,x
	sta literalEmitOffset
	lda literalOffset+1,x
	sta literalEmitOffset+1
	lda literalLength,x
	sta literalEmitRemaining
	inc literalEmitRemaining		; include NUL; token length < 255
	lda #$00
	sta literalEmitColumn
.bytes:
	lda literalEmitRemaining
	beq .newline
	lda literalEmitColumn
	beq .noComma
	lda #','
	jsr emit_output_byte
	bcc .failed
.noComma:
	lda #'$'
	jsr emit_output_byte
	bcc .failed
	clc
	lda #<literalBytes
	adc literalEmitOffset
	sta EMIT_PTR
	lda #>literalBytes
	adc literalEmitOffset+1
	sta EMIT_PTR+1
	ldy #$00
	lda (EMIT_PTR),y
	jsr emit_hex_byte
	bcc .failed
	inc literalEmitOffset
	bne .offsetOk
	inc literalEmitOffset+1
.offsetOk:
	inc literalEmitColumn
	dec literalEmitRemaining
	jmp .bytes
.newline:
	jmp emit_newline
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Target assembly emission
;;; ---------------------------------------------------------------------------

emit_load_literal:
	lda #exprLdaImmEnd-exprLdaImm
	ldx #<exprLdaImm
	ldy #>exprLdaImm
	jsr emit_text
	bcc .failed
	lda expressionLiteralValue
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprLdxImmEnd-exprLdxImm
	ldx #<exprLdxImm
	ldy #>exprLdxImm
	jsr emit_text
	bcc .failed
	lda expressionLiteralValue+1
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_load_literal_address:
	lda #exprLdaLowImmEnd-exprLdaLowImm
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_text
	bcc .failed
	lda currentLiteralIndex
	jsr emit_literal_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprLdxHighImmEnd-exprLdxHighImm
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_text
	bcc .failed
	lda currentLiteralIndex
	jsr emit_literal_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_load_primary_scalar:
	lda primarySymbolArea
	cmp #SYMBOL_AREA_CURRENT
	beq .current
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	lda #exprLdxSpaceEnd-exprLdxSpace
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcc .failed
	jmp emit_plus_one_newline
.current:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_current_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda primarySymbolType
	cmp #TYPE_CHAR
	beq emit_zero_high
	lda #exprLdxSpaceEnd-exprLdxSpace
	ldx #<exprLdxSpace
	ldy #>exprLdxSpace
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_current_name
	bcc .failed
	jmp emit_plus_one_newline
.failed:
	clc
	rts

emit_zero_high:
	lda #exprLdxZeroEnd-exprLdxZero
	ldx #<exprLdxZero
	ldy #>exprLdxZero
	jmp emit_text

emit_load_primary_address:
	lda #exprLdaLowImmEnd-exprLdaLowImm
	ldx #<exprLdaLowImm
	ldy #>exprLdaLowImm
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprLdxHighImmEnd-exprLdxHighImm
	ldx #<exprLdxHighImm
	ldy #>exprLdxHighImm
	jsr emit_text
	bcc .failed
	ldx primarySymbolIndex
	jsr emit_persistent_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_plus_one_newline:
	lda #exprPlusOneEnd-exprPlusOne
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_text
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_spill_definition:
	sta emitSpillIndex
	jsr emit_spill_name
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

emit_store_spill:
	sta emitSpillIndex
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcc .failed
	lda emitSpillIndex
	jsr emit_spill_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprStxSpaceEnd-exprStxSpace
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_text
	bcc .failed
	lda emitSpillIndex
	jsr emit_spill_name
	bcc .failed
	jmp emit_plus_one_newline
.failed:
	clc
	rts

;;; X=current-function symbol index; expressionValueType target value in A/X.
emit_store_current_value:
	stx emitSavedIndex
	lda #exprStaSpaceEnd-exprStaSpace
	ldx #<exprStaSpace
	ldy #>exprStaSpace
	jsr emit_text
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx emitSavedIndex
	lda currentType,x
	cmp #TYPE_CHAR
	beq .done
	lda #exprStxSpaceEnd-exprStxSpace
	ldx #<exprStxSpace
	ldy #>exprStxSpace
	jsr emit_text
	bcc .failed
	ldx emitSavedIndex
	jsr emit_current_name
	bcc .failed
	jsr emit_plus_one_newline
	bcc .failed
.done:
	ldx emitSavedIndex
	sec
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

emit_unary_minus:
	lda #exprNegateEnd-exprNegate
	ldx #<exprNegate
	ldy #>exprNegate
	jmp emit_text

emit_binary_reduction:
	lda reduceOperator
	cmp #OP_ADD
	beq emit_add_reduction
	cmp #OP_SUB
	beq emit_sub_reduction
	cmp #OP_MUL
	beq emit_mul_reduction
	cmp #OP_AND
	beq emit_and_reduction
	cmp #OP_OR
	beq emit_or_reduction
	cmp #OP_SHL
	beq emit_shl_reduction
	cmp #OP_SHR
	beq emit_shr_reduction
	jmp emit_compare_reduction

emit_save_right_tmp:
	lda #exprSaveRightEnd-exprSaveRight
	ldx #<exprSaveRight
	ldy #>exprSaveRight
	jmp emit_text

emit_lda_reduce_spill:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	lda reduceSpill
	jsr emit_spill_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_lda_reduce_spill_high:
	lda #exprLdaSpaceEnd-exprLdaSpace
	ldx #<exprLdaSpace
	ldy #>exprLdaSpace
	jsr emit_text
	bcc .failed
	lda reduceSpill
	jsr emit_spill_name
	bcc .failed
	jmp emit_plus_one_newline
.failed:
	clc
	rts

emit_add_reduction:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprAddLowEnd-exprAddLow
	ldx #<exprAddLow
	ldy #>exprAddLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprAddHighEnd-exprAddHigh
	ldx #<exprAddHigh
	ldy #>exprAddHigh
	jmp emit_text
.failed:
	clc
	rts

emit_sub_reduction:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprSubLowEnd-exprSubLow
	ldx #<exprSubLow
	ldy #>exprSubLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprSubHighEnd-exprSubHigh
	ldx #<exprSubHigh
	ldy #>exprSubHigh
	jmp emit_text
.failed:
	clc
	rts

emit_and_reduction:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprAndLowEnd-exprAndLow
	ldx #<exprAndLow
	ldy #>exprAndLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprAndHighEnd-exprAndHigh
	ldx #<exprAndHigh
	ldy #>exprAndHigh
	jmp emit_text
.failed:
	clc
	rts

emit_or_reduction:
	jsr emit_save_right_tmp
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprOrLowEnd-exprOrLow
	ldx #<exprOrLow
	ldy #>exprOrLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprOrHighEnd-exprOrHigh
	ldx #<exprOrHigh
	ldy #>exprOrHigh
	jmp emit_text
.failed:
	clc
	rts

emit_mul_reduction:
	lda #exprMulSaveLowEnd-exprMulSaveLow
	ldx #<exprMulSaveLow
	ldy #>exprMulSaveLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprStaTmpEnd-exprStaTmp
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprMulTailEnd-exprMulTail
	ldx #<exprMulTail
	ldy #>exprMulTail
	jmp emit_text
.failed:
	clc
	rts

emit_shl_reduction:
	lda #$01
	sta shiftLeftFlag
	jmp emit_shift_reduction
emit_shr_reduction:
	lda #$00
	sta shiftLeftFlag

emit_shift_reduction:
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

	lda #exprShiftCountEnd-exprShiftCount
	ldx #<exprShiftCount
	ldy #>exprShiftCount
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprStaTmpEnd-exprStaTmp
	ldx #<exprStaTmp
	ldy #>exprStaTmp
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprStaTmpHighEnd-exprStaTmpHigh
	ldx #<exprStaTmpHigh
	ldy #>exprStaTmpHigh
	jsr emit_text
	bcc .failed
	lda #exprCpyZeroEnd-exprCpyZero
	ldx #<exprCpyZero
	ldy #>exprCpyZero
	jsr emit_text
	bcc .failed
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_text
	bcc .failed
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed

	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda shiftLeftFlag
	beq .right
	lda #exprShiftLeftBodyEnd-exprShiftLeftBody
	ldx #<exprShiftLeftBody
	ldy #>exprShiftLeftBody
	jmp .body
.right:
	lda #exprShiftRightBodyEnd-exprShiftRightBody
	ldx #<exprShiftRightBody
	ldy #>exprShiftRightBody
.body:
	jsr emit_text
	bcc .failed
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_text
	bcc .failed
	lda shiftLoopLabel
	sta emitLabelValue
	lda shiftLoopLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda shiftDoneLabel
	sta emitLabelValue
	lda shiftDoneLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #exprLoadTmpResultEnd-exprLoadTmpResult
	ldx #<exprLoadTmpResult
	ldy #>exprLoadTmpResult
	jmp emit_text
.failed:
	clc
	rts

;;; Comparisons use three nearby internal labels. Equality ignores signedness;
;;; relational operators choose signed or unsigned ordering from operand types.
emit_compare_reduction:
	jsr emit_save_right_tmp
	bcc .failed
	jsr reserve_compare_labels
	lda reduceOperator
	cmp #OP_EQ
	beq .eq
	cmp #OP_NE
	beq .ne
	jsr combined_integer_type
	cmp #TYPE_UNSIGNED
	beq .unsignedRel
	jmp emit_signed_relational
.unsignedRel:
	jmp emit_unsigned_relational
.eq:
	lda #$00
	sta compareInvert
	jmp emit_equality
.ne:
	lda #$01
	sta compareInvert
	jmp emit_equality
.failed:
	clc
	rts

reserve_compare_labels:
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareTrueLabel
	lda emitLabelValue+1
	sta compareTrueLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareFalseLabel
	lda emitLabelValue+1
	sta compareFalseLabel+1
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareDoneLabel
	lda emitLabelValue+1
	sta compareDoneLabel+1
	rts

emit_equality:
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcc .failed
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_text
	bcc .failed
	lda compareInvert
	beq .firstFalse
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jmp .firstLabel
.firstFalse:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
.firstLabel:
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprCmpTmpHighEnd-exprCmpTmpHigh
	ldx #<exprCmpTmpHigh
	ldy #>exprCmpTmpHigh
	jsr emit_text
	bcc .failed
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_text
	bcc .failed
	lda compareInvert
	beq .secondTrue
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jmp .secondLabel
.secondTrue:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
.secondLabel:
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda compareInvert
	beq .fallFalse
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jmp .fallLabel
.fallFalse:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
.fallLabel:
	jsr emit_jump_label
	bcc .failed
	jmp emit_comparison_result_labels
.failed:
	clc
	rts

;;; Unsigned high-byte then low-byte comparison. The branch choices are kept
;;; explicit rather than encoded in a clever table so the 6502 ordering is easy
;;; to audit.
emit_unsigned_relational:
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprCmpTmpHighEnd-exprCmpTmpHigh
	ldx #<exprCmpTmpHigh
	ldy #>exprCmpTmpHigh
	jsr emit_text
	bcc .failed
	lda reduceOperator
	cmp #OP_LT
	beq .ltle
	cmp #OP_LE
	beq .ltle
	jmp .gtge
.ltle:
	jsr emit_bcc_true
	bcc .failed
	jsr emit_bne_false
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcc .failed
	lda reduceOperator
	cmp #OP_LT
	beq .lowLt
	jsr emit_bcc_true
	bcc .failed
	jsr emit_beq_true
	bcc .failed
	jmp .fallFalse
.lowLt:
	jsr emit_bcc_true
	bcc .failed
	jmp .fallFalse
.gtge:
	jsr emit_bcc_false
	bcc .failed
	jsr emit_bne_true
	bcc .failed
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprCmpTmpEnd-exprCmpTmp
	ldx #<exprCmpTmp
	ldy #>exprCmpTmp
	jsr emit_text
	bcc .failed
	lda reduceOperator
	cmp #OP_GT
	beq .lowGt
	jsr emit_bcc_false
	bcc .failed
	jmp .fallTrue
.lowGt:
	jsr emit_bcc_false
	bcc .failed
	jsr emit_beq_false
	bcc .failed
.fallTrue:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed
	jmp emit_comparison_result_labels
.fallFalse:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed
	jmp emit_comparison_result_labels
.failed:
	clc
	rts

;;; Signed relational: if signs differ, the sign of the left operand decides;
;;; with equal signs ordinary unsigned byte ordering is already correct.
emit_signed_relational:
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprEorTmpHighEnd-exprEorTmpHigh
	ldx #<exprEorTmpHigh
	ldy #>exprEorTmpHigh
	jsr emit_text
	bcc .failed
	jsr reserve_generated_label
	lda emitLabelValue
	sta compareSameSignLabel
	lda emitLabelValue+1
	sta compareSameSignLabel+1
	lda #exprBplEnd-exprBpl
	ldx #<exprBpl
	ldy #>exprBpl
	jsr emit_text
	bcc .failed
	lda compareSameSignLabel
	sta emitLabelValue
	lda compareSameSignLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda reduceOperator
	cmp #OP_LT
	beq .negativeTrue
	cmp #OP_LE
	beq .negativeTrue
	jsr emit_bmi_false
	bcc .failed
	jmp .signTrue
.negativeTrue:
	jsr emit_bmi_true
	bcc .failed
	jmp .signFalse
.signTrue:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed
	jmp .sameSign
.signFalse:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed
.sameSign:
	lda compareSameSignLabel
	sta emitLabelValue
	lda compareSameSignLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .failed
	jmp emit_unsigned_relational
.failed:
	clc
	rts

emit_bcc_true:
	lda #exprBccEnd-exprBcc
	ldx #<exprBcc
	ldy #>exprBcc
	jsr emit_text
	bcc .failed
	jmp emit_true_label_newline
.failed:
	clc
	rts
emit_bcc_false:
	lda #exprBccEnd-exprBcc
	ldx #<exprBcc
	ldy #>exprBcc
	jsr emit_text
	bcc .failed
	jmp emit_false_label_newline
.failed:
	clc
	rts
emit_bne_true:
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_text
	bcc .failed
	jmp emit_true_label_newline
.failed:
	clc
	rts
emit_bne_false:
	lda #exprBneEnd-exprBne
	ldx #<exprBne
	ldy #>exprBne
	jsr emit_text
	bcc .failed
	jmp emit_false_label_newline
.failed:
	clc
	rts
emit_beq_true:
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_text
	bcc .failed
	jmp emit_true_label_newline
.failed:
	clc
	rts
emit_beq_false:
	lda #exprBeqEnd-exprBeq
	ldx #<exprBeq
	ldy #>exprBeq
	jsr emit_text
	bcc .failed
	jmp emit_false_label_newline
.failed:
	clc
	rts
emit_bmi_true:
	lda #exprBmiEnd-exprBmi
	ldx #<exprBmi
	ldy #>exprBmi
	jsr emit_text
	bcc .failed
	jmp emit_true_label_newline
.failed:
	clc
	rts
emit_bmi_false:
	lda #exprBmiEnd-exprBmi
	ldx #<exprBmi
	ldy #>exprBmi
	jsr emit_text
	bcc .failed
	jmp emit_false_label_newline
.failed:
	clc
	rts

emit_true_label_newline:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts
emit_false_label_newline:
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_jump_label:
	lda #exprJmpEnd-exprJmp
	ldx #<exprJmp
	ldy #>exprJmp
	jsr emit_text
	bcc .failed
	jsr emit_generated_label_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_label_definition:
	jsr emit_generated_label_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_comparison_result_labels:
	lda compareTrueLabel
	sta emitLabelValue
	lda compareTrueLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .failed
	lda #exprTrueValueEnd-exprTrueValue
	ldx #<exprTrueValue
	ldy #>exprTrueValue
	jsr emit_text
	bcc .failed
	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jsr emit_jump_label
	bcc .failed
	lda compareFalseLabel
	sta emitLabelValue
	lda compareFalseLabel+1
	sta emitLabelValue+1
	jsr emit_label_definition
	bcc .failed
	lda #exprFalseValueEnd-exprFalseValue
	ldx #<exprFalseValue
	ldy #>exprFalseValue
	jsr emit_text
	bcc .failed
	lda compareDoneLabel
	sta emitLabelValue
	lda compareDoneLabel+1
	sta emitLabelValue+1
	jmp emit_label_definition
.failed:
	clc
	rts

;;; Index value is in target A/X. reduceSpill holds the saved base address and
;;; reduceLeftType is the array/pointer element type.
emit_index_load:
	jsr emit_save_right_tmp
	bcc .failed
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .scaled
	lda #exprScaleIndexEnd-exprScaleIndex
	ldx #<exprScaleIndex
	ldy #>exprScaleIndex
	jsr emit_text
	bcc .failed
.scaled:
	jsr emit_lda_reduce_spill
	bcc .failed
	lda #exprIndexLowEnd-exprIndexLow
	ldx #<exprIndexLow
	ldy #>exprIndexLow
	jsr emit_text
	bcc .failed
	jsr emit_lda_reduce_spill_high
	bcc .failed
	lda #exprIndexHighEnd-exprIndexHigh
	ldx #<exprIndexHigh
	ldy #>exprIndexHigh
	jsr emit_text
	bcc .failed
	lda reduceLeftType
	cmp #TYPE_CHAR
	beq .charLoad
	lda #exprWordIndirectEnd-exprWordIndirect
	ldx #<exprWordIndirect
	ldy #>exprWordIndirect
	jmp emit_text
.charLoad:
	lda #exprCharIndirectEnd-exprCharIndirect
	ldx #<exprCharIndirect
	ldy #>exprCharIndirect
	jmp emit_text
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Fixed target-source fragments. Keeping the actual 6502 sequences visible
;;; here makes code generation auditable without decoding an opcode/template IR.
;;; ---------------------------------------------------------------------------

exprLdaImm:		byte $09,'l','d','a',' ','#','$'
exprLdaImmEnd:
exprLdxImm:		byte $09,'l','d','x',' ','#','$'
exprLdxImmEnd:
exprLdaLowImm:		byte $09,'l','d','a',' ','#','<'
exprLdaLowImmEnd:
exprLdxHighImm:		byte $09,'l','d','x',' ','#','>'
exprLdxHighImmEnd:
exprLdaSpace:		byte $09,'l','d','a',' '
exprLdaSpaceEnd:
exprLdxSpace:		byte $09,'l','d','x',' '
exprLdxSpaceEnd:
exprStaSpace:		byte $09,'s','t','a',' '
exprStaSpaceEnd:
exprStxSpace:		byte $09,'s','t','x',' '
exprStxSpaceEnd:
exprLdxZero:		byte $09,'l','d','x',' ','#','$','0','0',$0a
exprLdxZeroEnd:
exprPlusOne:		byte '+','1'
exprPlusOneEnd:
exprBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
exprBssAssignEnd:
exprBytePrefix:		byte $09,'b','y','t','e',' '
exprBytePrefixEnd:

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
exprNegateEnd:

exprSaveRight:
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','x',' ','N','C','_','T','M','P','+','1',$0a
exprSaveRightEnd:
exprAddLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAddLowEnd:
exprAddHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAddHighEnd:
exprSubLow:
	byte $09,'s','e','c',$0a
	byte $09,'s','b','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprSubLowEnd:
exprSubHigh:
	byte $09,'s','b','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprSubHighEnd:
exprAndLow:
	byte $09,'a','n','d',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprAndLowEnd:
exprAndHigh:
	byte $09,'a','n','d',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprAndHighEnd:
exprOrLow:
	byte $09,'o','r','a',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
exprOrLowEnd:
exprOrHigh:
	byte $09,'o','r','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte $09,'t','y','a',$0a
exprOrHighEnd:

exprMulSaveLow:		byte $09,'t','a','y',$0a
exprMulSaveLowEnd:
exprStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
exprStaTmpEnd:
exprStaTmpHigh:		byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
exprStaTmpHighEnd:
exprMulTail:
	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','y','a',$0a
	byte $09,'j','s','r',' ','_','_','n','c','_','m','u','l','1','6',$0a
exprMulTailEnd:

exprShiftCount:		byte $09,'t','a','y',$0a
exprShiftCountEnd:
exprCpyZero:		byte $09,'c','p','y',' ','#','$','0','0',$0a
exprCpyZeroEnd:
exprShiftLeftBody:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'d','e','y',$0a
exprShiftLeftBodyEnd:
exprShiftRightBody:
	byte $09,'l','s','r',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','T','M','P',$0a
	byte $09,'d','e','y',$0a
exprShiftRightBodyEnd:
exprLoadTmpResult:
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
	byte $09,'l','d','x',' ','N','C','_','T','M','P','+','1',$0a
exprLoadTmpResultEnd:

exprCmpTmp:		byte $09,'c','m','p',' ','N','C','_','T','M','P',$0a
exprCmpTmpEnd:
exprCmpTmpHigh:		byte $09,'c','m','p',' ','N','C','_','T','M','P','+','1',$0a
exprCmpTmpHighEnd:
exprEorTmpHigh:		byte $09,'e','o','r',' ','N','C','_','T','M','P','+','1',$0a
exprEorTmpHighEnd:
exprBcc:		byte $09,'b','c','c',' '
exprBccEnd:
exprBne:		byte $09,'b','n','e',' '
exprBneEnd:
exprBeq:		byte $09,'b','e','q',' '
exprBeqEnd:
exprBmi:		byte $09,'b','m','i',' '
exprBmiEnd:
exprBpl:		byte $09,'b','p','l',' '
exprBplEnd:
exprJmp:		byte $09,'j','m','p',' '
exprJmpEnd:
exprTrueValue:
	byte $09,'l','d','a',' ','#','$','0','1',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprTrueValueEnd:
exprFalseValue:
	byte $09,'l','d','a',' ','#','$','0','0',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprFalseValueEnd:

exprScaleIndex:
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
exprScaleIndexEnd:
exprIndexLow:
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
exprIndexLowEnd:
exprIndexHigh:
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R','+','1',$0a
exprIndexHighEnd:
exprCharIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
exprCharIndirectEnd:
exprWordIndirect:
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'s','t','a',' ','N','C','_','T','M','P',$0a
	byte $09,'i','n','y',$0a
	byte $09,'l','d','a',' ','(','N','C','_','P','T','R',')',',','y',$0a
	byte $09,'t','a','x',$0a
	byte $09,'l','d','a',' ','N','C','_','T','M','P',$0a
exprWordIndirectEnd:

;;; Compiler state: one bounded operator stack plus narrow transient fields.
operatorCount:		byte 0
operatorKind:		ds EXPR_STACK_CAPACITY
operatorSpill:		ds EXPR_STACK_CAPACITY
operatorType:		ds EXPR_STACK_CAPACITY
expressionSpillDepth:	byte 0
spillAllocatedCount:	byte 0
expressionNeedValue:	byte 0
expressionValueType:	byte TYPE_INT
expressionIndexable:	byte 0
expressionArrayOnly:	byte 0
expressionElementType:	byte TYPE_CHAR
expressionError:	byte EXPR_OK
pendingOperator:	byte 0
pendingPrecedence:	byte 0
wantedMarker:		byte 0
reduceOperator:		byte 0
reduceSpill:		byte 0
reduceLeftType:		byte TYPE_INT
reduceRightType:	byte TYPE_INT
reduceResultType:	byte TYPE_INT
primarySymbolIndex:	byte 0
primarySymbolArea:	byte SYMBOL_AREA_NONE
primarySymbolKind:	byte 0
primarySymbolType:	byte TYPE_INT
expressionLiteralValue:	word 0
emitSpillIndex:		byte 0
shiftLeftFlag:		byte 0
shiftLoopLabel:		word 0
shiftDoneLabel:		word 0
compareTrueLabel:	word 0
compareFalseLabel:	word 0
compareDoneLabel:	word 0
compareSameSignLabel:	word 0
compareInvert:		byte 0

;;; Narrow deferred literal pool. Offsets/lengths are 16-bit because the byte
;;; pool is deliberately independent of scanner token length.
literalCount:		byte 0
literalBytesUsed:	word 0
literalOffset:		ds EXPR_LITERAL_CAPACITY*2
literalLength:		ds EXPR_LITERAL_CAPACITY*2
literalBytes:		ds EXPR_LITERAL_BYTES
currentLiteralIndex:	byte 0
literalNewEnd:		word 0
literalEmitIndex:	byte 0
literalEmitOffset:	word 0
literalEmitRemaining:	byte 0
literalEmitColumn:	byte 0
