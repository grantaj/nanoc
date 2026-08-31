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
	jsr scalar_assignment_type_ok
	bcc .badTarget
	lda currentTokenKind
	cmp #';'
	beq .store
.badTarget:
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

;;; Indexed assignment follows the literal machine shape from phase1-machine.md:
;;; compute the complete lvalue address first, save it in static function storage,
;;; evaluate the RHS freely, restore NC_PTR, then store. Address arithmetic itself
;;; is shared with indexed reads through #55's emit_index_address.
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
;;; Compiler statement state
;;; ---------------------------------------------------------------------------

;;; Fixed control stack: each of 16 frames has one kind byte and two 16-bit label
;;; slots. The one-byte depth is separate. IF_TRUE versus IF_ELSE is explicit in
;;; the kind byte; no enum ordering carries semantics. BLOCK uses only kind.
controlDepth:		byte 0
controlKind:		ds CONTROL_STACK_CAPACITY
controlLabel0Lo:	ds CONTROL_STACK_CAPACITY
controlLabel0Hi:	ds CONTROL_STACK_CAPACITY
controlLabel1Lo:	ds CONTROL_STACK_CAPACITY
controlLabel1Hi:	ds CONTROL_STACK_CAPACITY

statementTargetIndex:	byte 0
statementTargetArea:	byte SYMBOL_AREA_NONE
statementTargetKind:	byte 0
statementTargetType:	byte TYPE_INT
statementElementType:	byte TYPE_CHAR
statementAddressAllocated:	byte 0

	include "statement_codegen.asm"