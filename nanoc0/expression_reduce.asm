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
;;; precedence >= the incoming one before pushing the incoming operator. Group,
;;; index and call markers are hard boundaries.
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
	cmp #OP_CALL
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
	cmp #OP_CALL
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
	lda operatorValueKind,x
	sta reduceLeftKind
	lda operatorValueLow,x
	sta reduceLeftLow
	lda operatorValueHigh,x
	sta reduceLeftHigh
	lda operatorType,x
	sta reduceLeftType
	dec operatorCount
	jsr emit_index_load
	bcs .emitted
	jmp expression_emit_fail
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
	cmp #OP_CALL
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
	lda operatorValueKind,x
	sta reduceLeftKind
	lda operatorValueLow,x
	sta reduceLeftLow
	lda operatorValueHigh,x
	sta reduceLeftHigh
	lda operatorType,x
	sta reduceLeftType
	lda expressionValueKind
	sta reduceRightKind
	lda expressionValueLow
	sta reduceRightLow
	lda expressionValueHigh
	sta reduceRightHigh
	lda expressionValueType
	sta reduceRightType
	jsr validate_binary_types
	bcs .typesOk
	rts
.typesOk:
	jsr emit_binary_reduction
	bcs .emitted
	jmp expression_emit_fail
.emitted:
	dec operatorCount
	jmp finish_binary_result
.bad:
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail

;;; Every reduction finishes with the same type/indexability bookkeeping.
finish_binary_result:
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

