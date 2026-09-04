;;; calls.asm
;;;
;;; Nano C Phase 1 function-call parser state.
;;;
;;; Calls are delimiters inside the existing non-recursive expression machine.
;;; OP_CALL sits on the ordinary operator stack while one small parallel frame
;;; remembers the callee, the next argument number, and the operator-stack index
;;; of that marker. The frame index itself is the pending-call depth.
;;;
;;; Arguments that must survive later argument expressions use the bounded 6502
;;; hardware stack. For a C-defined function the final argument stays naturally in
;;; A/X; if earlier arguments must be restored, Y holds its low byte while PLA/STA
;;; copies those earlier values to their fixed slots. The callee stores the final
;;; parameter once at function entry. Runtime routines keep their established
;;; static-slot interface. Nested calls naturally nest these short lifetimes;
;;; Phase 1 has no recursion or re-entrancy.
;;;
;;; bootstrap/ass.c currently needs at most five arguments. Eight leaves modest
;;; headroom. Four pending calls comfortably covers the deliberately nested
;;; Phase 1 cases without making the compiler tables arbitrary.

CALL_STACK_CAPACITY    = 4
CALL_ARGUMENT_CAPACITY = 8

;;; Pending-call arrays are compiler work RAM immediately after the expression
;;; literal pool. They contain no initial data, and their fixed addresses are
;;; declared before use for the one-pass native assembler.
callCallee            = $b330
callArgumentIndex     = $b334
callOperatorBase      = $b338
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
	sta indexUsed
.loop:
	sta runtimeParamAllocated,x
	sta runtimeUsed,x
	inx
	cpx #RUNTIME_SYMBOL_COUNT
	bne .loop
	rts

;;; reset_call_function_state
reset_call_function_state:
	lda #$00
	sta callDepth
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
	jsr preserve_pending_values_for_call
	bcs .pendingPreserved
	jmp expression_emit_fail
.pendingPreserved:
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
	lda #VALUE_NONE
	sta operatorValueKind,y
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
;;; currentToken is ','. Finish and preserve the current argument, then advance to
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
;;; currentToken is ')' for a non-empty call. The final argument has no later
;;; expression to survive. Prepare its natural call-boundary form, then restore
;;; earlier arguments from the hardware stack before emitting the JSR.
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
;;; A comma means more source follows, so this completed value really does need a
;;; short lifetime across later argument evaluation.
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
;;; hardware-stack preservation or the final direct parameter store.
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
;;; The bounded hardware stack is the natural home for a value whose only
;;; lifetime is "until the rest of this call's arguments have been evaluated".
stage_current_call_argument:
	jsr prepare_current_call_argument
	bcc .failed
	jsr emit_push_call_argument
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
;;; No later argument exists. A C-defined callee receives this final value directly
;;; in A/X and stores it once at entry. Runtime routines retain their static slots.
;;; With earlier arguments below it on the hardware stack, Y preserves the low byte
;;; while those PLA/STA restores run; X already carries the high byte and survives.
store_final_call_argument:
	jsr prepare_current_call_argument
	bcc .failed
	ldx callEmitCallee
	lda persistentKind,x
	cmp #SYMBOL_RUNTIME_FUNCTION
	beq .runtime
	jsr materialize_call_argument
	bcc .failed
	ldx callEmitDepth
	inc callArgumentIndex,x
	lda callArgumentIndex,x
	cmp #$02
	bcc .done
	ldx #<exprTay
	ldy #>exprTay
	jsr emit_string
	bcc .emitFailed
.done:
	sec
	rts
.runtime:
	jsr ensure_runtime_parameter_slots
	bcc .failed
	jsr prepare_current_call_argument
	bcc .failed
	jsr emit_store_callee_argument
	bcc .emitFailed
	ldx callEmitDepth
	inc callArgumentIndex,x
	sec
	rts
.emitFailed:
	lda #EXPR_EMIT_ERROR
	jmp expression_fail
.failed:
	clc
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
	;;; Earlier arguments were pushed in source order, so restore them in reverse.
	;;; A C-defined final argument remains in A/X (or Y/X while these restores run);
	;;; runtime calls have already stored their final argument in the fixed slot.
	lda callEmitArgumentCount
	beq .call
	sec
	sbc #$01
	sta callCopyIndex
.copyLoop:
	lda callCopyIndex
	beq .call
	dec callCopyIndex
	lda callCopyIndex
	sta callEmitArgument
	ldx callEmitCallee
	lda persistentParamStart,x
	clc
	adc callEmitArgument
	tax
	lda parameterType,x
	sta callEmitParamType
	jsr emit_pop_call_argument
	bcs .copyLoop
	lda #EXPR_EMIT_ERROR
	jmp expression_fail

.call:
	;;; For a C-defined multi-argument call, Y has preserved the final low byte
	;;; while the earlier static parameter slots were restored.
	ldx callEmitCallee
	lda persistentKind,x
	cmp #SYMBOL_RUNTIME_FUNCTION
	beq .emitCall
	lda callEmitArgumentCount
	cmp #$02
	bcc .emitCall
	ldx #<exprTya
	ldy #>exprTya
	jsr emit_string
	bcc .callEmitFailed
.emitCall:
	jsr emit_call_instruction
	bcs .called
.callEmitFailed:
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

;;; Scalar call state is reset or assigned before use. It follows the expression
;;; formatter scratch in the same compiler work-RAM region.
callDepth                    = $b3f2
callBeginCallee              = $b3f3
callEmitDepth                = $b3f4
callEmitArgument             = $b3f5
callEmitArgumentCount        = $b3f6
callEmitCallee               = $b3f7
callEmitParamType            = $b3f8
callCopyIndex                = $b3f9
callRuntimeArgument          = $b3fa
callStatementMode            = $b3fb
callStatementSawOuter        = $b3fc
callStatementTerminator      = $b3fd
