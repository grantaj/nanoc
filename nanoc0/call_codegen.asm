;;; call_codegen.asm
;;;
;;; Literal target-code spelling for calls.asm.
;;;
;;; Earlier arguments whose lifetime crosses later argument evaluation use PHA.
;;; A C-defined function receives its final argument directly in A/X; Y preserves
;;; the low byte only while earlier values are PLA'd into their slots. Runtime
;;; functions retain their fixed-slot ABI. This is exactly the short lifetime the
;;; 6502 registers/stack already represent; there is no caller staging BSS.

;;; The #56 statement regression still names its original call-primary seam. Its
;;; fixture now reaches the real #57 wrong-argument-count diagnostic.
EXPR_CALL_UNAVAILABLE = EXPR_CALL_ARGUMENT_COUNT

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

;;; Target A/X holds an argument that must survive later arguments. char needs
;;; one byte; word/pointer arguments push low then high so the reverse pop sees
;;; high first.
emit_push_call_argument:
	lda callEmitParamType
	cmp #TYPE_CHAR
	bne .word
	jsr materialize_expression_byte
	bcc .failed
	ldx #<callPha
	ldy #>callPha
	jmp emit_string
.word:
	jsr materialize_expression_word
	bcc .failed
	ldx #<callPushWord
	ldy #>callPushWord
	jmp emit_string
.failed:
	clc
	rts


;;; Put the prepared argument into its call-boundary register width without storing it.
materialize_call_argument:
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .byte
	jmp materialize_expression_word
.byte:
	jmp materialize_expression_byte

;;; Runtime calls keep the established fixed callee parameter slot.
emit_store_callee_argument:
	jsr materialize_call_argument
	bcs .prepared
	clc
	rts
.prepared:
	jmp emit_store_call_registers_to_callee

;;; Store the already-prepared A/X call registers into callEmitCallee/Argument.
;;; C-defined function entries use this once for their final parameter; runtime
;;; callers use the same spelling at each call because those routines have no C
;;; entry prologue.
emit_store_call_registers_to_callee:
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

;;; Restore one earlier argument from the hardware stack. Word/pointer values
;;; were pushed low then high, so pop high first and low second.
emit_pop_call_argument:
	lda callEmitParamType
	cmp #TYPE_CHAR
	beq .byte
	ldx #<callPlaSta
	ldy #>callPlaSta
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jsr emit_plus_one_call_newline
	bcc .failed
.byte:
	ldx #<callPlaSta
	ldy #>callPlaSta
	jsr emit_string
	bcc .failed
	jsr emit_callee_parameter_name
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; A call may freely change target flags. It therefore ends the lifetime of a
;;; comparison's useful Z flag even when that comparison appeared in an argument.
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
	jmp mark_expression_ax
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
callValueSuffix:	byte '_','_','v',0
callBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$',0
callStaSpace:		byte $09,'s','t','a',' ',0
callStxSpace:		byte $09,'s','t','x',' ',0
callPha:		byte $09,'p','h','a',$0a,0
callPushWord:		byte $09,'p','h','a',$0a,$09,'t','x','a',$0a,$09,'p','h','a',$0a,0
callPlaSta:		byte $09,'p','l','a',$0a,$09,'s','t','a',' ',0
callJsrSpace:		byte $09,'j','s','r',' ',0
callPlusOne:		byte '+','1',0
