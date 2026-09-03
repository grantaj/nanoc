;;; expression.asm
;;;
;;; Nano C Phase 1 expression parser.
;;;
;;; This is one explicit bounded state machine, not recursive descent. A current
;;; source operand stays in the cheapest 6502 form that still names it: literal,
;;; current/persistent scalar, fixed address, A, or A/X. Binary stack entries keep
;;; that small identity beside the operator. Only a value that genuinely has to
;;; survive later generated code is pushed on the 6502 hardware stack. The
;;; compiler retains no expression tree, RPN stream or generic IR.
;;;
;;; The important state is deliberately small:
;;;
;;;   operatorCount          entries currently on the one operator stack
;;;   operatorValueKind      physical/source form of each saved left operand
;;;   expressionNeedValue    parser expects a primary/unary, not an operator
;;;   expressionIndexable    current value may be followed by [index]
;;;   expressionMustIndex    non-char array address is only valid for [index]
;;;   callDepth              live pending calls, handled by calls.asm
;;;
;;; expression_codegen.asm contains the literal 6502 sequences emitted by
;;; reductions. expression_immediate.asm contains the small operand-formatting
;;; helpers used to spell direct immediate and named-memory instructions.
;;;
;;; Function calls use OP_CALL on this same operator stack. Commas and the call's
;;; closing ')' reduce only the current argument back to that marker; calls.asm
;;; retains the tiny parallel pending-call facts and emits staging/copy/JSR code.

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
EXPR_CALL_DEPTH_OVERFLOW    = 11
EXPR_CALL_ARGUMENT_OVERFLOW = 12
EXPR_CALL_ARGUMENT_COUNT    = 13
EXPR_CALL_ARGUMENT_TYPE     = 14

EXPR_STACK_CAPACITY   = 16
EXPR_LITERAL_CAPACITY = 16
EXPR_LITERAL_BYTES    = 512
EXPR_LITERAL_ROW      = 16

RIGHT_START_NORMAL   = 0
RIGHT_START_CAPTURED = 1
RIGHT_START_UPDATED  = 2

VALUE_NONE        = 0
VALUE_LITERAL     = 1
VALUE_CURRENT     = 2
VALUE_PERSISTENT  = 3
VALUE_STRING      = 4
VALUE_ARRAY       = 5
VALUE_A           = 6
VALUE_AX          = 7
VALUE_STACK_BYTE  = 8
VALUE_STACK_WORD  = 9
VALUE_COND_EQ      = 10
VALUE_COND_NE      = 11
VALUE_COND_LT      = 12
VALUE_COND_GE      = 13
VALUE_COND_GT      = 14
VALUE_COND_LE      = 15

;;; Scalar assignment and expression parsing share these two temporary target
;;; states. Define them here, before expression code can reference them: native
;;; ass is deliberately one-pass and does not turn a forward label into a later
;;; constant definition.
STATEMENT_SCALAR_ASSIGNMENT = $82
STATEMENT_SELF_UPDATE       = $83

INDEXABLE_POINTER     = 1
INDEXABLE_FIXED_ARRAY = 2

;;; Mutable expression tables are compiler work RAM, not loaded data. Define the
;;; fixed map before parser code references it so native ass sees constants, not
;;; forward labels that are later redefined.
operatorKind      = $b0c0
operatorValueLow  = $b0d0
operatorType      = $b0e0
literalOffset     = $b0f0
literalLength     = $b110
literalBytes      = $b130

;;; Two more bytes per operator live after emit.asm's four-byte KERNAL scratch
;;; save area. They are compiler work RAM, not loaded program data.
operatorValueKind = $b3a0
operatorValueHigh = $b3b0

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
OP_CALL  = 17

PREC_MUL   = 70
PREC_ADD   = 60
PREC_SHIFT = 50
PREC_REL   = 40
PREC_EQ    = 30
PREC_AND   = 20
PREC_OR    = 10

;;; reset_expression_translation_state
;;; Literal bytes, generated labels and runtime-call state belong to one
;;; translation unit.
reset_expression_translation_state:
	lda #$00
	sta literalCount
	sta literalBytesUsed
	sta literalBytesUsed+1
	jsr reset_generated_labels
	jsr reset_call_translation_state
	jmp reset_expression_function_state

;;; reset_expression_function_state
reset_expression_function_state:
	lda #$00
	sta operatorCount
	sta expressionError
	jsr reset_call_function_state
	rts

;;; parse_expression
;;; Compile one expression beginning at currentToken. The first token that is
;;; not part of it remains current for the caller, normally ';', ')' or ']'.
;;; Commas belonging to calls are consumed internally by the same state machine.
;;; Carry set means expressionValueType describes the result and
;;; expressionValueKind says whether it is still nameable or materialised.
;;;
;;; A scanner failure is already fully described by parserError/scannerError.
;;; Expression code therefore returns it unchanged rather than relabelling it as
;;; a malformed primary.
parse_expression:
	lda #EXPR_OK
	sta expressionError
	lda #$00
	sta operatorCount
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
	;;; A non-empty call has only opened its OP_CALL marker. Its first argument is
	;;; current now, so return directly to the value side of this same loop.
	lda expressionNeedValue
	beq .primaryActions
	jmp .value
.primaryActions:
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
	cmp #','
	bne .notComma
	jsr call_delimiter_belongs_to_call
	bcs .callComma
	jmp .finish
.callComma:
	jsr finish_call_separator
	bcs .callCommaDone
	rts
.callCommaDone:
	jmp .value

.notComma:
	cmp #')'
	bne .notCloseGroup
	jsr call_delimiter_belongs_to_call
	bcs .callClose
	jmp .closeGroup
.callClose:
	jsr finish_call_close
	bcs .callClosed
	rts
.callClosed:
	jmp .primaryActions

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
	jsr push_pending_binary
	bcs .binaryPushed
	rts
.binaryPushed:
	jsr parser_next
	bcs .rightStarted
	rts
.rightStarted:
	jsr try_scalar_self_update_rhs
	bcs .rightChecked
	rts
.rightChecked:
	lda rightStartState
	cmp #RIGHT_START_UPDATED
	beq .updated
	cmp #RIGHT_START_CAPTURED
	beq .captured
	lda #$01
	sta expressionNeedValue
	jmp .value
.captured:
	jmp .primaryActions
.updated:
	jmp .operator

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

expression_emit_fail:
	lda #EXPR_EMIT_ERROR
expression_fail:
	sta expressionError
	clc
	rts


;;; The parser stays one bounded state machine; these includes only keep its
;;; concrete source/lifetime/reduction sections readable in assembly source.
	include "expression_operands.asm"
	include "expression_reduce.asm"
	include "expression_literals.asm"

;;; ---------------------------------------------------------------------------
;;; Expression compiler state
;;; ---------------------------------------------------------------------------

;;; One bounded operator stack. Group/index/call markers use the same arrays as
;;; binary operators so nesting needs no recursive parser state. Their mutable
;;; arrays use the fixed work-RAM constants declared above.
operatorCount:		byte 0
expressionNeedValue:	byte 0
expressionValueType:	byte TYPE_INT
expressionValueKind:	byte VALUE_AX
expressionValueLow:	byte 0
expressionValueHigh:	byte 0
expressionIndexable:	byte 0
expressionMustIndex:	byte 0
expressionElementType:	byte TYPE_CHAR
expressionError:	byte EXPR_OK
pendingOperator:	byte 0
pendingPrecedence:	byte 0
rightStartState:	byte RIGHT_START_NORMAL
wantedMarker:		byte 0
reduceOperator:		byte 0
reduceLeftKind:		byte VALUE_AX
reduceLeftLow:		byte 0
reduceLeftHigh:		byte 0
reduceRightKind:	byte VALUE_AX
reduceRightLow:		byte 0
reduceRightHigh:	byte 0
reduceLeftType:		byte TYPE_INT
reduceRightType:	byte TYPE_INT
preserveOperatorIndex:	byte 0
reduceResultType:	byte TYPE_INT
primarySymbolIndex:	byte 0
primarySymbolArea:	byte SYMBOL_AREA_NONE
primarySymbolKind:	byte 0
primarySymbolType:	byte TYPE_INT

;;; Narrow deferred literal pool. Offsets/lengths are 16-bit so this storage is
;;; independent of the scanner's reusable token width. Its mutable tables and
;;; bytes use the fixed work-RAM constants above; only counters/scratch are loaded.
literalCount:		byte 0
literalBytesUsed:	word 0
currentLiteralIndex:	byte 0
literalNewEnd:		word 0
literalEmitIndex:	byte 0
literalEmitOffset:	word 0
literalEmitRemaining:	byte 0
literalEmitColumn:	byte 0