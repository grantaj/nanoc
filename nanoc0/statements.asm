;;; statements.asm
;;;
;;; Nano C Phase 1 executable statement parser.
;;;
;;; One current token and one explicit bounded control stack are enough for the
;;; Phase 1 statement grammar. Source constructs emit target assembly as soon as
;;; they are understood; statement_codegen.asm contains the spelling routines,
;;; not a retained statement representation.
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
CONTROL_FRAME_BYTES    = 5

;;; Five bytes per frame: kind plus two 16-bit labels. These 80 mutable bytes
;;; follow the call workspace and are compiler work RAM, not loaded data. Define
;;; them before use so native ass sees fixed constants rather than forward labels.
controlKind     = $b34a
controlLabel0Lo = $b35a
controlLabel0Hi = $b36a
controlLabel1Lo = $b37a
controlLabel1Hi = $b38a

CONTROL_BLOCK   = 1
CONTROL_IF_TRUE = 2
CONTROL_IF_ELSE = 3
CONTROL_WHILE   = 4

;;; Temporary statementTargetKind values after a byte-index lvalue has been
;;; recognized. The next identifier statement overwrites them normally. Scalar
;;; assignment states are defined in expression.asm, before their first use.
STATEMENT_INDEX_ARRAY       = $80
STATEMENT_INDEX_CURRENT_PTR = $81

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
	lda controlDepth
	bne .closeNested
	;;; No unfinished frame means this is the function's own closing brace.
	lda #EMIT_LABEL_GENERIC
	sta emitLabelKind
	jsr parser_next
	rts
.closeNested:
	jsr close_statement_body
	bcc .failed
	jmp .loop
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
;;; source block consumes a BLOCK frame. Function-brace handling stays in the
;;; main loop where depth zero is visible directly.
close_statement_body:
	ldx controlDepth
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
	lda #EMIT_LABEL_IF_FALSE
	sta emitLabelKind
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
	lda #EMIT_LABEL_IF_FALSE
	sta emitLabelKind
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
	lda #EMIT_LABEL_IF_END
	sta emitLabelKind
	jsr emit_jump_label
	bcc .emitFail

	ldx controlDepth
	dex
	lda controlLabel0Lo,x
	sta emitLabelValue
	lda controlLabel0Hi,x
	sta emitLabelValue+1
	lda #EMIT_LABEL_IF_FALSE
	sta emitLabelKind
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
	lda #EMIT_LABEL_IF_END
	sta emitLabelKind
	jsr emit_label_definition
	bcc .emitFail
	dec controlDepth
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

parse_while_statement:
	jsr ensure_control_space
	bcs .haveSpace
	rts
.haveSpace:
	ldx controlDepth
	jsr reserve_generated_label
	lda emitLabelValue
	sta controlLabel0Lo,x
	lda emitLabelValue+1
	sta controlLabel0Hi,x
	lda #EMIT_LABEL_WHILE_TOP
	sta emitLabelKind
	jsr emit_label_definition
	bcc .emitFail

	ldx controlDepth
	jsr reserve_generated_label
	lda emitLabelValue
	sta controlLabel1Lo,x
	lda emitLabelValue+1
	sta controlLabel1Hi,x

	jsr parser_next
	bcs .haveWhileToken
	rts
.haveWhileToken:
	lda currentTokenKind
	cmp #'('
	beq .haveOpen
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveOpen:
	jsr parser_next
	bcs .haveConditionToken
	rts
.haveConditionToken:
	jsr parse_condition_expression
	bcs .conditionDone
	rts
.conditionDone:
	lda currentTokenKind
	cmp #')'
	beq .haveClose
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.haveClose:
	jsr parser_next
	bcs .haveBodyToken
	rts
.haveBodyToken:
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
	lda #EMIT_LABEL_WHILE_END
	sta emitLabelKind
	jsr emit_statement_false_jump
	bcc .emitFail
	jmp parser_next
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
	lda #EMIT_LABEL_WHILE_TOP
	sta emitLabelKind
	jsr emit_jump_label
	bcc .emitFail

	ldx controlDepth
	dex
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1
	lda #EMIT_LABEL_WHILE_END
	sta emitLabelKind
	jsr emit_label_definition
	bcc .emitFail
	dec controlDepth
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

parse_break_statement:
	ldx controlDepth
.search:
	cpx #$00
	beq .outside
	dex
	lda controlKind,x
	cmp #CONTROL_WHILE
	bne .search
	lda controlLabel1Lo,x
	sta emitLabelValue
	lda controlLabel1Hi,x
	sta emitLabelValue+1
	lda #EMIT_LABEL_WHILE_END
	sta emitLabelKind

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
	jsr emit_return_value
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

;;; Resolve the identifier while its source spelling is still current. A known
;;; function is handed straight back to the one expression parser so call
;;; statements and call primaries share exactly the same argument machinery.
;;; Non-functions retain only the small semantic identity needed after the
;;; reusable token is replaced.
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
	lda statementTargetKind
	cmp #SYMBOL_FUNCTION
	beq .callStatement
	cmp #SYMBOL_RUNTIME_FUNCTION
	beq .callStatement
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
	bne .bad
	jmp parse_indexed_assignment
.callStatement:
	jmp parse_call_statement_expression
.bad:
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.failed:
	clc
	rts

;;; Calls are the sole Phase 1 expression statements. The expression entry point
;;; stops immediately after the outer call closes; therefore `f()+1;` is still
;;; rejected here rather than silently broadening the language to arbitrary
;;; expression statements.
parse_call_statement_expression:
	jsr parse_call_expression_statement
	bcs .parsed
	jmp statement_expression_failed
.parsed:
	lda currentTokenKind
	cmp #';'
	beq .done
	lda #PARSE_BAD_STATEMENT
	jmp parser_fail
.done:
	jmp parser_next

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
	;;; expression.asm may narrow this marker to the exact `x = x +/- 1` form.
	lda #STATEMENT_SCALAR_ASSIGNMENT
	sta statementTargetKind
	jsr parser_next
	bcc .failed
	jsr parse_expression
	bcs .rhsParsed
	jmp statement_expression_failed
.rhsParsed:
	jsr scalar_assignment_type_ok
	bcc .badTarget
	lda currentTokenKind
	cmp #';'
	beq .store
.badTarget:
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.store:
	ldx statementTargetKind
	lda #$00
	sta statementTargetKind
	cpx #STATEMENT_SELF_UPDATE
	bne .ordinaryStore
	jsr emit_direct_scalar_update
	bcc .emitFail
	jmp parser_next
.ordinaryStore:
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

;;; Integer destinations accept the three integer value types. A char pointer is
;;; deliberately narrower: Phase 1 pointer assignment is from another char *;
;;; integer/pointer casts are not part of the language.
scalar_assignment_type_ok:
	lda statementTargetType
	cmp #TYPE_CHAR_PTR
	beq .pointer
	lda expressionValueType
	jmp type_is_integer
.pointer:
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	beq .ok
	clc
	rts
.ok:
	sec
	rts

;;; Indexed assignment normally computes and saves the full lvalue address before
;;; the RHS. Two byte-index cases need less state: a fixed char array needs only
;;; its index, and a current-function char * can safely be reloaded after the RHS
;;; because no callee can name this function's static parameter/local slot.
parse_indexed_assignment:
	jsr validate_indexed_target
	bcc .badTarget
	jsr parser_next
	bcs .indexStarted
.failed:
	clc
	rts
.indexStarted:
	jsr parse_expression
	bcs .indexParsed
	jmp statement_expression_failed
.indexParsed:
	lda expressionValueType
	jsr type_is_integer
	bcc .badTarget
	lda currentTokenKind
	cmp #']'
	bne .badTarget

	lda statementElementType
	cmp #TYPE_CHAR
	bne .fullAddress
	lda expressionValueType
	cmp #TYPE_CHAR
	bne .fullAddress
	lda statementTargetKind
	cmp #SYMBOL_ARRAY
	beq .directArray
	lda statementTargetArea
	cmp #SYMBOL_AREA_CURRENT
	bne .fullAddress
	lda #STATEMENT_INDEX_CURRENT_PTR
	jmp .saveIndex
.directArray:
	lda #STATEMENT_INDEX_ARRAY
.saveIndex:
	sta statementTargetKind
	jsr ensure_statement_address_slot
	bcc .failed
	jsr emit_save_statement_index
	bcc .emitFail
	jmp .addressDone

.badTarget:
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail

.fullAddress:
	jsr emit_statement_index_address
	bcc .emitFail
	jsr ensure_statement_address_slot
	bcc .failed
	jsr emit_save_statement_address
	bcc .emitFail
.addressDone:
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
	lda expressionValueType
	jsr type_is_integer
	bcc .badTarget
	lda currentTokenKind
	cmp #';'
	beq .store
	lda #PARSE_BAD_ASSIGNMENT
	jmp parser_fail
.store:
	jsr emit_indexed_store
	bcc .emitFail
	jmp parser_next
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

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
;;; Compiler statement state
;;; ---------------------------------------------------------------------------

;;; The fixed control stack uses the work-RAM constants declared above. The
;;; one-byte depth and remaining transient statement state stay in loaded data.
controlDepth:		byte 0

statementTargetIndex:	byte 0
statementTargetArea:	byte SYMBOL_AREA_NONE
statementTargetKind:	byte 0
statementTargetType:	byte TYPE_INT
statementElementType:	byte TYPE_CHAR
statementAddressAllocated:	byte 0

	include "statement_codegen.asm"