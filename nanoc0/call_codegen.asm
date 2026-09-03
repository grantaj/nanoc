;;; call_codegen.asm
;;;
;;; Literal target-code spelling for calls.asm.
;;;
;;; Earlier arguments that must survive later source use caller staging. Width is
;;; now decided by the known callee parameter: a char stages only A, while a real
;;; int/unsigned/pointer consumer asks the expression seam for a complete A/X.
;;; The call itself remains one direct JSR; #89 owns any calling-convention change.

;;; The #56 statement regression still names its original call-primary seam. Its
;;; fixture now reaches the real #57 wrong-argument-count diagnostic.
EXPR_CALL_UNAVAILABLE = EXPR_CALL_ARGUMENT_COUNT

;;; callEmitDepth/callEmitArgument -> __c_<caller>__aDD_AA
emit_call_stage_name:
	ldx #<callCPrefix
	ldy #>callCPrefix
	jsr emit_string
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	ldx #<callStageSuffix
	ldy #>callStageSuffix
	jsr emit_string
	bcc .failed
	lda callEmitDepth
	jsr emit_hex_byte
	bcc .failed
	lda #'_'
	jsr emit_output_byte
	bcc .failed
	lda callEmitArgument
	jmp emit_hex_byte
.failed:
	clc
	rts

;;; callEmitCallee/callEmitArgument -> __c_<callee>__vAA
emit_callee_parameter_name:
	ldx #<callCPrefix
	ldy #>callCPrefix
	jsr emit_string
	bcc .failed
	ldx callEmitCallee
	jsr emit_persistent_source_name
	bcc .failed
	ldx #<callValueSuffix
	ldy #>callValueSuffix
	jsr emit_string
	bcc .failed
	lda callEmitArgument
	jmp emit_hex_byte
.failed:
	clc
	rts

emit_call_stage_definition:
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_call_bss_assignment
	rts
.failed:
	clc
	rts

emit_runtime_parameter_definition:
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_call_bss_assignment
	rts
.failed:
	clc
	rts

emit_call_bss_assignment:
	ldx #<callBssAssign
	ldy #>callBssAssign
	jsr emit_string
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

;;; The parameter type says how much of the argument must survive later source.
emit_store_call_stage:
	lda callEmitParamType
	cmp #TYPE_CHAR
	bne .word
	jsr ensure_expression_byte_value
	bcc .failed
	jmp .low
.word:
	jsr ensure_expression_word
	bcc .failed
.low:
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_string
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .done
	ldx #<callStxSpace
	ldy #>callStxSpace
	jsr emit_string
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

;;; The final argument needs no caller-owned staging. Store only the width the
;;; fixed callee parameter can observe.
emit_store_callee_argument:
	lda callEmitParamType
	cmp #TYPE_CHAR
	bne .word
	jsr ensure_expression_byte_value
	bcc .failed
	jmp .low
.word:
	jsr ensure_expression_word
	bcc .failed
.low:
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .done
	ldx #<callStxSpace
	ldy #>callStxSpace
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

;;; Copy one staged argument to its fixed callee-owned parameter slot. char uses
;;; only the low byte; every other Phase 1 parameter type copies both bytes.
emit_copy_call_argument:
	ldx #<callLdaSpace
	ldy #>callLdaSpace
	jsr emit_string
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .done

	ldx #<callLdaSpace
	ldy #>callLdaSpace
	jsr emit_string
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

;;; A call may freely change target registers and flags. Phase 1 functions still
;;; return int for #88, so the new result is a complete A/X word with no live
;;; condition. #89 owns any narrower/native return convention.
emit_call_instruction:
	ldx #<callJsrSpace
	ldy #>callJsrSpace
	jsr emit_string
	bcc .failed
	ldx callEmitCallee
	jsr emit_persistent_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	jmp mark_expression_word
.failed:
	clc
	rts

emit_plus_one_call_newline:
	ldx #<callPlusOne
	ldy #>callPlusOne
	jsr emit_string
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

callCPrefix:		byte '_','_','c','_',0
callStageSuffix:	byte '_','_','a',0
callValueSuffix:	byte '_','_','v',0
callBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$',0
callStaSpace:		byte $09,'s','t','a',' ',0
callStxSpace:		byte $09,'s','t','x',' ',0
callLdaSpace:		byte $09,'l','d','a',' ',0
callJsrSpace:		byte $09,'j','s','r',' ',0
callPlusOne:		byte '+','1',0
