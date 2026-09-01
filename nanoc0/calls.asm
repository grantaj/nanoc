;;; calls.asm
;;;
;;; Nano C Phase 1 function-call parser state.
;;;
;;; Calls are delimiters inside the existing non-recursive expression machine.
;;; OP_CALL sits on the ordinary operator stack while one small parallel frame
;;; remembers the callee, the next argument number, and the operator-stack index
;;; of that marker. The frame index itself is the call/staging depth.
;;;
;;; Arguments that must survive later argument expressions are reduced to A/X and
;;; emitted to caller-owned static staging. The final argument has no later source
;;; to survive, so it goes straight from A/X to the callee parameter slot. After
;;; the closing ')' the earlier staged words are copied and a direct JSR emitted.
;;; No C value is ever placed on the 6502 hardware stack.
;;;
;;; bootstrap/ass.c currently needs at most five arguments. Eight leaves modest
;;; headroom. Four pending calls comfortably covers the deliberately nested
;;; Phase 1 cases without making the compiler tables arbitrary.

CALL_STACK_CAPACITY    = 4
CALL_ARGUMENT_CAPACITY = 8
CALL_FRAME_BYTES       = 3

;;; Pending-call arrays are compiler work RAM immediately after the expression
;;; literal pool. They contain no initial data, and their fixed addresses are
;;; declared before use for the one-pass native assembler.
callCallee            = $b330
callArgumentIndex     = $b334
callOperatorBase      = $b338
callStageAllocated    = $b33c
runtimeParamAllocated = $b340
runtimeUsed           = $b345

;;; reset_call_translation_state
;;; Runtime parameter slots, runtime use and compiler-private support use belong
;;; to the whole generated translation unit.
reset_call_translation_state:
	ldx #$00
	lda #$00
	sta compareUsed
	sta multiplyUsed
.loop:
	sta runtimeParamAllocated,x
	sta runtimeUsed,x
	inx
	cpx #RUNTIME_SYMBOL_COUNT
	bne .loop
	rts

;;; reset_call_function_state
;;; Staging is caller-owned, so each new C function gets a fresh set of reusable
;;; depth/argument names. BSS allocated for earlier functions remains allocated.
reset_call_function_state:
	lda #$00
	sta callDepth
	ldx #$00
.loop:
	sta callStageAllocated,x
	inx
	cpx #CALL_STACK_CAPACITY
	bne .loop
	rts

;;; parse_call_expression_statement
;;; The statement grammar permits a call primary as a statement, but not a
;;; general expression statement. Run the ordinary expression engine and remember
;;; the token immediately following its first completed outer call. It must be
;;; ';'. This keeps all argument parsing in one place while rejecting `f()+1;`.
parse_call_expression_statement:
	lda #$01
	sta callStatementMode
	lda #$00
	sta callStatementSawOuter
	jsr parse_expression
	php
	lda #$00
	sta callStatementMode
	plp
	bcc .failed
	lda callStatementSawOuter
	beq .bad
	lda callStatementTerminator
	cmp #';'
	beq .ok
.bad:
	lda #EXPR_BAD_PRIMARY
	jmp expression_fail
.ok:
	sec
	rts
.failed:
	clc
	rts

;;; expression_call_primary
;;; X=known persistent function symbol. currentToken is '('.
;;;
;;; A non-empty call returns with expressionNeedValue=1 and currentToken on the
;;; first argument token; the ordinary expression loop continues from there.
;;; A zero-argument call is completed immediately and returns a finished primary.
expression_call_primary:
	stx callBeginCallee
	lda callDepth
	cmp #CALL_STACK_CAPACITY
	bcc .depthOk
	lda #EXPR_CALL_DEPTH_OVERFLOW
	jmp expression_fail
.depthOk:
	ldx callBeginCallee
	lda persistentParamCount,x
	cmp #CALL_ARGUMENT_CAPACITY+1
	bcc .argumentCapacityOk
	lda #EXPR_CALL_ARGUMENT_OVERFLOW
	jmp expression_fail
.argumentCapacityOk:
	lda operatorCount
	cmp #EXPR_STACK_CAPACITY
	bcc .operatorSpace
	lda #EXPR_STACK_OVERFLOW
	jmp expression_fail
.operatorSpace:
	ldx callDepth
	lda callBeginCallee
	sta callCallee,x
	lda #$00
	sta callArgumentIndex,x
	lda operatorCount
	sta callOperatorBase,x

	ldy operatorCount
	lda #OP_CALL
	sta operatorKind,y
	inc operatorCount
	inc callDepth

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #')'
	bne .arguments
	jsr complete_current_call
	bcc .failed
	lda #$00
	sta expressionNeedValue
	sec
	rts
.arguments:
	lda #$01
	sta expressionNeedValue
	sec
	rts
.failed:
	clc
	rts

;;; call_delimiter_belongs_to_call
;;; Carry set when the nearest unmatched delimiter marker is OP_CALL. This is
;;; used for both ',' and ')'. A nearer ordinary '(' or '[' means the delimiter
;;; cannot close/separate the pending call yet.
call_delimiter_belongs_to_call:
	ldx operatorCount
.loop:
	cpx #$00
	beq .notCall
	dex
	lda operatorKind,x
	cmp #OP_CALL
	beq .call
	cmp #OP_GROUP
	beq .notCall
	cmp #OP_INDEX
	beq .notCall
	jmp .loop
.call:
	sec
	rts
.notCall:
	clc
	rts

;;; finish_call_separator
;;; currentToken is ','. Finish and stage the current argument, then advance to
;;; the first token of the next one.
finish_call_separator:
	jsr finish_current_call_argument
	bcc .failed
	jsr parser_next
	bcc .failed
	lda #$01
	sta expressionNeedValue
	lda #$00
	sta expressionIndexable
	sta expressionMustIndex
	sec
	rts
.failed:
	clc
	rts

;;; finish_call_close
;;; currentToken is ')' for a non-empty call. The final argument no longer needs
;;; caller staging: no later argument expression can clobber it. Store it directly
;;; in the callee slot, copy only the earlier staged values, then emit the JSR.
finish_call_close:
	jsr finish_current_call_value
	bcc .failed
	jsr store_final_call_argument
	bcc .failed
	jmp complete_current_call
.failed:
	clc
	rts

;;; finish_current_call_argument
;;; A comma means more source follows, so this completed value really does need
;;; caller staging before the next argument is evaluated.
finish_current_call_argument:
	jsr finish_current_call_value
	bcc .failed
	jsr stage_current_call_argument
	bcc .failed
	sec
	rts
.failed:
	clc
	rts

;;; finish_current_call_value
;;; Reduce only operators belonging to this argument and verify that OP_CALL is
;;; exactly the active marker. On success the complete argument value is in A/X.
finish_current_call_value:
	lda expressionNeedValue
	beq .haveValue
	lda #EXPR_EXPECTED_VALUE
	jmp expression_fail
.haveValue:
	lda #OP_CALL
	jsr reduce_to_marker
	bcs .marker
	lda expressionError
	bne .failed
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail
.marker:
	jsr verify_current_call_marker
	rts
.failed:
	clc
	rts

;;; verify_current_call_marker
;;; After reducing an argument the active OP_CALL must be exactly the marker
;;; recorded by the top pending-call frame.
verify_current_call_marker:
	lda callDepth
	beq .bad
	sec
	sbc #$01
	tax
	lda operatorCount
	beq .bad
	sec
	sbc #$01
	cmp callOperatorBase,x
	bne .bad
	tay
	lda operatorKind,y
	cmp #OP_CALL
	bne .bad
	sec
	rts
.bad:
	lda #EXPR_UNMATCHED_DELIMITER
	jmp expression_fail

;;; prepare_current_call_argument
;;; Resolve the active callee/argument and check the source value against the
;;; known parameter type. The small callEmit* fields are then ready for either
;;; caller staging or the final direct parameter store.
prepare_current_call_argument:
	lda callDepth
	sec
	sbc #$01
	sta callEmitDepth
	tax
	lda callArgumentIndex,x
	sta callEmitArgument
	lda callCallee,x
	sta callEmitCallee
	tax

	lda callEmitArgument
	cmp persistentParamCount,x
	bcc .argumentExists
	lda #EXPR_CALL_ARGUMENT_COUNT
	jmp expression_fail
.argumentExists:
	lda persistentParamStart,x
	clc
	adc callEmitArgument
	tax
	lda parameterType,x
	sta callEmitParamType
	cmp #TYPE_CHAR_PTR
	beq .pointerParameter
	lda expressionValueType
	jsr type_is_integer
	bcs .typeOk
	lda #EXPR_CALL_ARGUMENT_TYPE
	jmp expression_fail
.pointerParameter:
	lda expressionValueType
	cmp #TYPE_CHAR_PTR
	beq .typeOk
	lda #EXPR_CALL_ARGUMENT_TYPE
	jmp expression_fail
.typeOk:
	sec
	rts

;;; stage_current_call_argument
;;; A comma means this value must survive later argument evaluation. Allocate the
;;; caller depth/argument word lazily and save A/X there.
stage_current_call_argument:
	jsr prepare_current_call_argument
	bcc .failed
	jsr ensure_call_stage_slot
	bcc .failed
	jsr emit_store_call_stage
	bcs .stored
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.stored:
	ldx callEmitDepth
	inc callArgumentIndex,x
	sec
	rts
.failed:
	clc
	rts

;;; store_final_call_argument
;;; No later argument exists, so A/X can go directly to the fixed callee slot.
;;; Runtime functions allocate those slots lazily; that allocator uses callEmit*
;;; as scratch, so prepare the argument once more afterwards before spelling it.
store_final_call_argument:
	jsr prepare_current_call_argument
	bcc .failed
	ldx callEmitCallee
	lda persistentKind,x
	cmp #SYMBOL_RUNTIME_FUNCTION
	bne .ready
	jsr ensure_runtime_parameter_slots
	bcc .failed
	jsr prepare_current_call_argument
	bcc .failed
.ready:
	jsr emit_store_callee_argument
	bcs .stored
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.stored:
	ldx callEmitDepth
	inc callArgumentIndex,x
	sec
	rts
.failed:
	clc
	rts

;;; ensure_call_stage_slot
;;; callStageAllocated[depth] is simply the number of two-byte argument words
;;; already allocated at that depth. Arguments are encountered in order, so a
;;; count is enough; there is no depth*argument allocation bitmap.
ensure_call_stage_slot:
	ldx callEmitDepth
	lda callEmitArgument
	cmp callStageAllocated,x
	bcc .allocated
	beq .allocate
	lda #EXPR_CALL_ARGUMENT_OVERFLOW
	jmp expression_fail
.allocate:
	lda #$02
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcs .bssOk
	lda #EXPR_BSS_OVERFLOW
	jmp expression_fail
.bssOk:
	jsr emit_call_stage_definition
	bcs .defined
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.defined:
	ldx callEmitDepth
	inc callStageAllocated,x
.allocated:
	sec
	rts

;;; complete_current_call
;;; currentToken is the call-closing ')'. No argument evaluation remains live.
;;; Runtime parameter slots are lazily allocated on first use because runtime
;;; functions have no C definition from which #54 could allocate them.
complete_current_call:
	jsr verify_current_call_marker
	bcs .markerOk
	rts
.markerOk:
	lda callDepth
	sec
	sbc #$01
	sta callEmitDepth
	tax
	lda callCallee,x
	sta callEmitCallee
	lda callArgumentIndex,x
	sta callEmitArgumentCount

	ldx callEmitCallee
	lda callEmitArgumentCount
	cmp persistentParamCount,x
	beq .countOk
	lda #EXPR_CALL_ARGUMENT_COUNT
	jmp expression_fail
.countOk:
	dec operatorCount

	lda persistentKind,x
	cmp #SYMBOL_RUNTIME_FUNCTION
	bne .copyArguments
	jsr ensure_runtime_parameter_slots
	bcs .runtimeReady
	rts
.runtimeReady:
	ldx callEmitCallee
	lda #$01
	sta runtimeUsed,x

.copyArguments:
	;;; The final argument is already in its callee slot. Zero-argument calls have
	;;; nothing to copy; otherwise stop when copyIndex+1 reaches the total count.
	lda callEmitArgumentCount
	beq .call
	lda #$00
	sta callCopyIndex
.copyLoop:
	lda callCopyIndex
	clc
	adc #$01
	cmp callEmitArgumentCount
	beq .call
	lda callCopyIndex
	sta callEmitArgument
	ldx callEmitCallee
	lda persistentParamStart,x
	clc
	adc callEmitArgument
	tax
	lda parameterType,x
	sta callEmitParamType
	jsr emit_copy_call_argument
	bcs .copied
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.copied:
	inc callCopyIndex
	jmp .copyLoop

.call:
	jsr emit_call_instruction
	bcs .called
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.called:
	dec callDepth
	ldx callEmitCallee
	lda persistentType,x
	sta expressionValueType
	lda #$00
	sta expressionIndexable
	sta expressionMustIndex
	sta expressionNeedValue
	jsr parser_next
	bcs .advanced
	rts
.advanced:
	;;; Only the first completed outer call matters for the statement grammar.
	;;; Later calls in a forbidden larger expression must not overwrite its
	;;; immediate terminator.
	lda callStatementMode
	beq .done
	lda callDepth
	bne .done
	lda callStatementSawOuter
	bne .done
	lda currentTokenKind
	sta callStatementTerminator
	lda #$01
	sta callStatementSawOuter
.done:
	sec
	rts

;;; Runtime function parameters use the same __c_<function>__vNN spelling as C
;;; parameters. Allocate those fixed slots the first time a given runtime entry
;;; is called; later callers all copy into the same callee-owned storage.
ensure_runtime_parameter_slots:
	ldx callEmitCallee
	lda runtimeParamAllocated,x
	beq .allocate
	sec
	rts
.allocate:
	lda #$00
	sta callRuntimeArgument
.loop:
	ldx callEmitCallee
	lda callRuntimeArgument
	cmp persistentParamCount,x
	beq .done
	sta callEmitArgument
	lda persistentParamStart,x
	clc
	adc callRuntimeArgument
	tax
	lda parameterType,x
	jsr set_alloc_size_for_type
	jsr allocate_bss
	bcs .bssOk
	lda #EXPR_BSS_OVERFLOW
	jmp expression_fail
.bssOk:
	jsr emit_runtime_parameter_definition
	bcs .defined
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.defined:
	inc callRuntimeArgument
	jmp .loop
.done:
	ldx callEmitCallee
	lda #$01
	sta runtimeParamAllocated,x
	sec
	rts

	include "call_codegen.asm"

;;; ---------------------------------------------------------------------------
;;; Pending-call compiler state
;;; ---------------------------------------------------------------------------

;;; The bounded arrays use the fixed compiler work-RAM constants declared above.
callDepth:		byte 0

;;; Transient call/codegen scratch.
callBeginCallee:	byte 0
callEmitDepth:		byte 0
callEmitArgument:	byte 0
callEmitArgumentCount:	byte 0
callEmitCallee:		byte 0
callEmitParamType:	byte TYPE_INT
callCopyIndex:		byte 0
callRuntimeArgument:	byte 0
callStatementMode:	byte 0
callStatementSawOuter:	byte 0
callStatementTerminator:	byte 0
