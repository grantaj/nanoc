;;; call_codegen.asm
;;;
;;; Literal target-code spelling for calls.asm.
;;;
;;; The generated shape remains deliberately visible:
;;;
;;;   evaluate argument -> A/X
;;;   STA/STX caller staging
;;;   ...
;;;   LDA staging / STA callee parameter
;;;   ...
;;;   JSR known callee
;;;
;;; There is no parameter-copy loop in the generated program and no ABI object.

;;; Temporary compatibility name for the #56 native seam test while #57 replaces
;;; that case with the real wrong-argument-count diagnostic.
EXPR_CALL_UNAVAILABLE = EXPR_CALL_ARGUMENT_COUNT

;;; callEmitDepth/callEmitArgument -> __c_<caller>__aDD_AA
emit_call_stage_name:
	lda #callCPrefixEnd-callCPrefix
	ldx #<callCPrefix
	ldy #>callCPrefix
	jsr emit_text
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	lda #callStageSuffixEnd-callStageSuffix
	ldx #<callStageSuffix
	ldy #>callStageSuffix
	jsr emit_text
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
	lda #callCPrefixEnd-callCPrefix
	ldx #<callCPrefix
	ldy #>callCPrefix
	jsr emit_text
	bcc .failed
	ldx callEmitCallee
	jsr emit_persistent_source_name
	bcc .failed
	lda #callValueSuffixEnd-callValueSuffix
	ldx #<callValueSuffix
	ldy #>callValueSuffix
	jsr emit_text
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
	lda #callBssAssignEnd-callBssAssign
	ldx #<callBssAssign
	ldy #>callBssAssign
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

;;; Target A/X currently holds the completed argument value.
emit_store_call_stage:
	lda #callStaSpaceEnd-callStaSpace
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_text
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #callStxSpaceEnd-callStxSpace
	ldx #<callStxSpace
	ldy #>callStxSpace
	jsr emit_text
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_plus_one_call_newline
	rts
.failed:
	clc
	rts

;;; Copy one staged argument to its fixed callee-owned parameter slot. char uses
;;; only the low byte; every other Phase 1 parameter type copies both bytes.
emit_copy_call_argument:
	lda #callLdaSpaceEnd-callLdaSpace
	ldx #<callLdaSpace
	ldy #>callLdaSpace
	jsr emit_text
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #callStaSpaceEnd-callStaSpace
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_text
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .done

	lda #callLdaSpaceEnd-callLdaSpace
	ldx #<callLdaSpace
	ldy #>callLdaSpace
	jsr emit_text
	bcc .failed
	jsr emit_call_stage_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
	lda #callStaSpaceEnd-callStaSpace
	ldx #<callStaSpace
	ldy #>callStaSpace
	jsr emit_text
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_plus_one_call_newline
	rts
.done:
	sec
	rts
.failed:
	clc
	rts

emit_call_instruction:
	lda #callJsrSpaceEnd-callJsrSpace
	ldx #<callJsrSpace
	ldy #>callJsrSpace
	jsr emit_text
	bcc .failed
	ldx callEmitCallee
	jsr emit_persistent_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_plus_one_call_newline:
	lda #callPlusOneEnd-callPlusOne
	ldx #<callPlusOne
	ldy #>callPlusOne
	jsr emit_text
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

callCPrefix:		byte '_','_','c','_'
callCPrefixEnd:
callStageSuffix:	byte '_','_','a'
callStageSuffixEnd:
callValueSuffix:	byte '_','_','v'
callValueSuffixEnd:
callBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
callBssAssignEnd:
callStaSpace:		byte $09,'s','t','a',' '
callStaSpaceEnd:
callStxSpace:		byte $09,'s','t','x',' '
callStxSpaceEnd:
callLdaSpace:		byte $09,'l','d','a',' '
callLdaSpaceEnd:
callJsrSpace:		byte $09,'j','s','r',' '
callJsrSpaceEnd:
callPlusOne:		byte '+','1'
callPlusOneEnd:
