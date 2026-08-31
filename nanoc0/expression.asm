;;; expression.asm
;;;
;;; Nano C Phase 1 expression parser.
;;;
;;; This is one explicit bounded state machine, not recursive descent. The
;;; generated program's current value is always in A/X. A binary left operand
;;; that must survive later source is emitted to a reusable fixed per-function
;;; spill slot. The compiler retains no expression tree, RPN stream or generic
;;; intermediate representation.
;;;
;;; The important state is deliberately small:
;;;
;;;   operatorCount          entries currently on the one operator stack
;;;   expressionSpillDepth   live saved left operands
;;;   spillAllocatedCount    spill words already reserved for this function
;;;   expressionNeedValue    parser expects a primary/unary, not an operator
;;;   expressionIndexable    current value may be followed by [index]
;;;   expressionMustIndex    non-char array address is only valid for [index]
;;;
;;; expression_codegen.asm contains the literal 6502 sequences emitted by
;;; reductions. Keeping those sequences separate makes the parser itself readable
;;; without introducing an abstraction between parsing and code generation.
;;;
;;; Calls are the one deliberately unfinished primary. The #55 stub fails at a
;;; call expression without consuming it; #57 replaces that one routine with the
;;; explicit pending-call state machine.

	include "emit.asm"

EXPR_OK                     = 0
EXPR_EXPECTED_VALUE         = 1
EXPR_STACK_OVERFLOW         = 2
EXPR_UNMATCHED_DELIMITER    = 3
EXPR_UNDECLARED             = 4
EXPR_BAD_PRIMARY            = 5
EXPR_BAD_TYPE               = 6
EXPR_BSS_OVERFLOW           = 7
EXPR_EMIT_ERROR             = 8
EXPR_LITERAL_COUNT_OVERFLOW = 9
EXPR_LITERAL_POOL_OVERFLOW  = 10
EXPR_CALL_UNAVAILABLE       = 11

EXPR_STACK_CAPACITY   = 16
EXPR_LITERAL_CAPACITY = 16
EXPR_LITERAL_BYTES    = 512
EXPR_LITERAL_ROW      = 16

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
;;; BSS remains allocated, but the new function has a new label namespace.
reset_expression_function_state:
	lda #$00
	sta operatorCount
	sta expressionSpillDepth
	sta spillAllocatedCount
	sta expressionError
	rts

;;; parse_expression
;;; Compile one expression beginning at currentToken. The first token that is
;;; not part of it remains current for the caller, normally ';', ',', ')' or ']'.
;;; Carry set means the generated value is in target A/X and
;;; expressionValueType describes it.
;;;
;;; A scanner failure is already fully described by parserError/scannerError.
;;; Expression code therefore returns it unchanged rather than relabelling it as
;;; a malformed primary.
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
	bne .notUnaryMinus
	jmp .unaryMinus
.notUnaryMinus:
	cmp #'('
	bne .primary
	jmp .openGroup
.primary:
	jsr parse_expression_primary
	bcs .primaryDone
	rts
.primaryDone:
	jsr reduce_unary_operators
	bcs .unaryDone
	rts
.unaryDone:
	jsr handle_postfix_index
	bcs .postfixDone
	rts
.postfixDone:
	lda expressionNeedValue
	beq .operator
	jmp .value

.unaryMinus:
	lda #OP_NEG
	jsr push_simple_operator
	bcs .unaryPushed
	rts
.unaryPushed:
	jsr parser_next
	bcs .unaryAdvanced
	rts
.unaryAdvanced:
	jmp .value

.openGroup:
	lda #OP_GROUP
	jsr push_simple_operator
	bcs .groupPushed
	rts
.groupPushed:
	jsr parser_next
	bcs .groupAdvanced
	rts
.groupAdvanced:
	jmp .value

.operator:
	lda currentTokenKind
	cmp #')'
	bne .notCloseGroup
	jmp .closeGroup
.notCloseGroup:
	cmp #']'
	bne .binaryCheck
	jmp .closeIndex

.binaryCheck:
	jsr binary_operator_for_token
	bcs .binaryOperator
	jmp .finish
.binaryOperator:
	sta pendingOperator
	jsr operator_precedence
	sty pendingPrecedence
	jsr reduce_for_precedence
	bcs .precedenceDone
	rts
.precedenceDone:
	jsr spill_current_value
	bcs .leftSpilled
	rts
.leftSpilled:
	jsr push_pending_binary
	bcs .binaryPushed
	rts
.binaryPushed:
	jsr parser_next
	bcs .binaryAdvanced
	rts
.binaryAdvanced:
	lda #$01
	sta expressionNeedValue
	jmp .value

.closeGroup:
	lda #OP_GROUP
	jsr reduce_to_marker
	bcs .groupMarker
	lda expressionError
	bne .failed
	jmp .finish
.groupMarker:
	jsr pop_group_marker
	bcs .groupPopped
	rts
.groupPopped:
	jsr parser_next
	bcs .groupAdvanced2
	rts
.groupAdvanced2:
	jsr reduce_unary_operators
	bcs .groupUnaryDone
	rts
.groupUnaryDone:
	jsr handle_postfix_index
	bcs .groupPostfixDone
	rts
.groupPostfixDone:
	lda expressionNeedValue
	bne .groupValue
	jmp .operator
.groupValue:
	jmp .value

.closeIndex:
	lda #OP_INDEX
	jsr reduce_to_marker
	bcs .indexMarker
	lda expressionError
	bne .failed
	jmp .finish
.indexMarker:
	jsr pop_index_marker
	bcs .indexPopped
	rts
.indexPopped:
	jsr parser_next
	bcs .indexAdvanced
	rts
.indexAdvanced:
	jsr reduce_unary_operators
	bcs .indexUnaryDone
	rts
.indexUnaryDone:
	jsr handle_postfix_index
	bcs .indexPostfixDone
	rts
.indexPostfixDone:
	lda expressionNeedValue
	bne .indexValue
	jmp .operator
.indexValue:
	jmp .value

.finish:
	lda expressionNeedValue
	beq .haveValue
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail
.haveValue:
	jsr reduce_all_operators
	bcs .reduced
	rts
.reduced:
	lda operatorCount
	beq .ok
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.ok:
	sec
	rts
.failed:
	clc
	rts

expression_fail:
	sta expressionError
	clc
	rts

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
	sta expressionLiteralValue
	lda currentTokenValue+1
	sta expressionLiteralValue+1
	lda currentTokenType
	cmp #TOKEN_TYPE_UNSIGNED
	bne .integerSigned
	lda #TYPE_UNSIGNED
	jmp .integerTypeDone
.integerSigned:
	lda #TYPE_INT
.integerTypeDone:
	sta expressionValueType
	jsr emit_load_literal
	bcs .integerEmitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.integerEmitted:
	jsr parser_next
	bcc .integerFailed
	jmp .primaryDone
.integerFailed:
	rts

.character:
	lda currentTokenValue
	sta expressionLiteralValue
	lda #$00
	sta expressionLiteralValue+1
	lda #TYPE_INT
	sta expressionValueType
	jsr emit_load_literal
	bcs .characterEmitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.characterEmitted:
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
	jsr emit_load_literal_address
	bcs .stringEmitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.stringEmitted:
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
	lda #$01
	sta expressionIndexable
	lda #TYPE_CHAR
	sta expressionElementType
.loadScalar:
	jsr emit_load_primary_scalar
	bcs .primaryDone
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

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
	sta expressionMustIndex
.arrayCanDecay:
	jsr emit_load_primary_address
	bcs .primaryDone
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

.function:
	lda currentTokenKind
	cmp #'('
	beq .call
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.call:
	ldx primarySymbolIndex
	jsr expression_call_primary
	bcs .primaryDone
	rts

.primaryDone:
	lda #$00
	sta expressionNeedValue
	sec
	rts

;;; #55 intentionally exposes the final call-primary seam but does not consume
;;; call syntax. #57 replaces this routine with the pending-call stack without
;;; changing the expression parser above.
expression_call_primary:
	lda #EXPR_CALL_UNAVAILABLE
	jmp expression_fail

;;; Postfix indexing uses a marker on the same explicit operator stack. The full
;;; 16-bit base address is spilled before the index expression begins.
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
	jsr spill_current_value
	bcs .baseSpilled
	rts
.baseSpilled:
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
	bcs .advanced
	rts
.advanced:
	lda #$01
	sta expressionNeedValue
	lda #$00
	sta expressionIndexable
	sta expressionMustIndex
	sec
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
;;; Save target A/X into the slot for expressionSpillDepth. Allocate that static
;;; word only the first time this function reaches the depth.
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
	bcs .definitionDone
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.definitionDone:
	inc spillAllocatedCount
.allocated:
	lda expressionSpillDepth
	jsr emit_store_spill
	bcs .stored
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.stored:
	inc expressionSpillDepth
	sec
	rts

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
	jsr emit_unary_minus
	bcs .emitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
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

;;; binary_operator_for_token
;;; Carry set: A=OP_*. Carry clear means the token terminates the expression.
;;; Precedence is deliberately looked up only by operator_precedence, so there is
;;; one authoritative description of the precedence table.
binary_operator_for_token:
	lda currentTokenKind
	cmp #'*'
	bne .notMul
	lda #OP_MUL
	sec
	rts
.notMul:
	cmp #'+'
	bne .notAdd
	lda #OP_ADD
	sec
	rts
.notAdd:
	cmp #'-'
	bne .notSub
	lda #OP_SUB
	sec
	rts
.notSub:
	cmp #TOKEN_SHL
	bne .notShl
	lda #OP_SHL
	sec
	rts
.notShl:
	cmp #TOKEN_SHR
	bne .notShr
	lda #OP_SHR
	sec
	rts
.notShr:
	cmp #'<'
	bne .notLt
	lda #OP_LT
	sec
	rts
.notLt:
	cmp #TOKEN_LE
	bne .notLe
	lda #OP_LE
	sec
	rts
.notLe:
	cmp #'>'
	bne .notGt
	lda #OP_GT
	sec
	rts
.notGt:
	cmp #TOKEN_GE
	bne .notGe
	lda #OP_GE
	sec
	rts
.notGe:
	cmp #TOKEN_EQ
	bne .notEq
	lda #OP_EQ
	sec
	rts
.notEq:
	cmp #TOKEN_NE
	bne .notNe
	lda #OP_NE
	sec
	rts
.notNe:
	cmp #'&'
	bne .notAnd
	lda #OP_AND
	sec
	rts
.notAnd:
	cmp #'|'
	bne .none
	lda #OP_OR
	sec
	rts
.none:
	clc
	rts

;;; A=OP_*; Y=precedence, or zero for a marker/unary kind.
operator_precedence:
	cmp #OP_MUL
	bne .notMul
	ldy #PREC_MUL
	rts
.notMul:
	cmp #OP_ADD
	beq .add
	cmp #OP_SUB
	bne .notAdd
.add:
	ldy #PREC_ADD
	rts
.notAdd:
	cmp #OP_SHL
	beq .shift
	cmp #OP_SHR
	bne .notShift
.shift:
	ldy #PREC_SHIFT
	rts
.notShift:
	cmp #OP_LT
	beq .rel
	cmp #OP_LE
	beq .rel
	cmp #OP_GT
	beq .rel
	cmp #OP_GE
	bne .notRel
.rel:
	ldy #PREC_REL
	rts
.notRel:
	cmp #OP_EQ
	beq .eq
	cmp #OP_NE
	bne .notEq
.eq:
	ldy #PREC_EQ
	rts
.notEq:
	cmp #OP_AND
	bne .notAnd
	ldy #PREC_AND
	rts
.notAnd:
	cmp #OP_OR
	bne .none
	ldy #PREC_OR
	rts
.none:
	ldy #$00
	rts

;;; All Phase 1 binary operators are left associative. Reduce an operator with
;;; precedence >= the incoming one before pushing the incoming operator.
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
	bcs .binaryDone
	rts
.binaryDone:
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcs .unaryDone
	rts
.unaryDone:
	jmp .loop
.done:
	sec
	rts

;;; A=marker kind. Binary operators above the marker are reduced. Carry clear
;;; with expressionError still zero means the delimiter belongs to the caller;
;;; carry clear with an error means malformed nesting/evaluation.
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
	bcs .binaryDone
	rts
.binaryDone:
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcs .unaryDone
	rts
.unaryDone:
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
	bcs .emitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.emitted:
	lda reduceLeftType
	sta expressionValueType
	lda #$00
	sta expressionMustIndex
	sta expressionIndexable
	sec
	rts
.badType:
	lda #EXPR_BAD_TYPE
	jmp expression_fail
.bad:
	lda #EXPR_UNMATCHED_DELIMITER
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
	bcs .binaryDone
	rts
.binaryDone:
	jmp .loop
.unary:
	jsr reduce_unary_operators
	bcs .unaryDone
	rts
.unaryDone:
	jmp .loop
.marker:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.done:
	sec
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
	bcs .typesOk
	rts
.typesOk:
	jsr emit_binary_reduction
	bcs .emitted
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.emitted:
	dec operatorCount
	dec expressionSpillDepth
	lda reduceResultType
	sta expressionValueType
	lda #$00
	sta expressionMustIndex
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

;;; Work only with the four Phase 1 scalar types. char promotes to int. Operator
;;; classes are spelled out explicitly; their meaning does not depend on OP_*
;;; numeric ordering.
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
	beq .comparison
	cmp #OP_LE
	beq .comparison
	cmp #OP_GT
	beq .comparison
	cmp #OP_GE
	beq .comparison
	cmp #OP_EQ
	beq .comparison
	cmp #OP_NE
	beq .comparison
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
;;; Called after executable/runtime output. Each literal is a label followed by
;;; ordinary byte directives. Rows are deliberately capped at 16 values so the
;;; generated source always stays well inside ass's 255-byte line buffer.
emit_deferred_literals:
	lda #$00
	sta literalEmitIndex
.loop:
	lda literalEmitIndex
	cmp literalCount
	beq .done
	jsr emit_one_literal
	bcs .emitted
	rts
.emitted:
	inc literalEmitIndex
	jmp .loop
.done:
	sec
	rts

emit_one_literal:
	lda literalEmitIndex
	jsr emit_literal_name
	bcs .colon
	rts
.colon:
	lda #':'
	jsr emit_output_byte
	bcs .labelDone
	rts
.labelDone:
	jsr emit_newline
	bcs .prepare
	rts
.prepare:
	lda literalEmitIndex
	asl
	tax
	lda literalOffset,x
	sta literalEmitOffset
	lda literalOffset+1,x
	sta literalEmitOffset+1
	lda literalLength,x
	sta literalEmitRemaining
	inc literalEmitRemaining		; include NUL; scanner text < 255 bytes
	lda #$00
	sta literalEmitColumn

.bytes:
	lda literalEmitRemaining
	beq .done
	lda literalEmitColumn
	bne .comma
	lda #exprBytePrefixEnd-exprBytePrefix
	ldx #<exprBytePrefix
	ldy #>exprBytePrefix
	jsr emit_text
	bcs .bytePrefixDone
	rts
.bytePrefixDone:
	jmp .byte
.comma:
	lda #','
	jsr emit_output_byte
	bcs .byte
	rts
.byte:
	lda #'$'
	jsr emit_output_byte
	bcs .byteAddress
	rts
.byteAddress:
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
	bcs .byteDone
	rts
.byteDone:
	inc literalEmitOffset
	bne .offsetOk
	inc literalEmitOffset+1
.offsetOk:
	inc literalEmitColumn
	dec literalEmitRemaining
	lda literalEmitRemaining
	beq .endRow
	lda literalEmitColumn
	cmp #EXPR_LITERAL_ROW
	bne .bytes
.endRow:
	jsr emit_newline
	bcs .rowDone
	rts
.rowDone:
	lda #$00
	sta literalEmitColumn
	lda literalEmitRemaining
	bne .bytes
.done:
	sec
	rts

;;; The output side is kept in a separate readable slab. Calls are direct; there
;;; is no intermediate representation or template-dispatch layer.
	include "expression_codegen.asm"
	include "expression_codegen_state.asm"

;;; ---------------------------------------------------------------------------
;;; Expression compiler state
;;; ---------------------------------------------------------------------------

;;; One bounded operator stack. Marker entries use the same arrays as binary
;;; operators so grouping and indexing need no recursive parser state.
operatorCount:		byte 0
operatorKind:		ds EXPR_STACK_CAPACITY
operatorSpill:		ds EXPR_STACK_CAPACITY
operatorType:		ds EXPR_STACK_CAPACITY
expressionSpillDepth:	byte 0
spillAllocatedCount:	byte 0
expressionNeedValue:	byte 0
expressionValueType:	byte TYPE_INT
expressionIndexable:	byte 0
expressionMustIndex:	byte 0
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

;;; Narrow deferred literal pool. Offsets/lengths are 16-bit so this storage is
;;; independent of the scanner's reusable token width.
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
