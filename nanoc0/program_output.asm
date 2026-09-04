;;; program_output.asm
;;;
;;; Concrete `ass` text emitted by the production nanoc0 driver.
;;;
;;; Declarations call four tiny hooks as storage facts become known. This file
;;; spells those facts directly as readable assembler source; it is not an
;;; intermediate representation and retains no copy of the generated program.

emit_persistent_symbol:
	stx callEmitCallee
	cmp #EMIT_STORAGE_BSS
	beq .bss

	;;; Data and functions are ordinary loaded text with a global label. A C-defined
	;;; function receives its final parameter in A/X and stores it once at entry,
	;;; rather than making every caller write that static slot.
.label:
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx callEmitCallee
	lda persistentKind,x
	cmp #SYMBOL_FUNCTION
	bne .labelDone
	jsr emit_function_final_parameter_store
	bcc .failed
.labelDone:
	sec
	rts

.bss:
	jsr emit_persistent_name
	bcc .failed
	jmp emit_program_bss_assignment
.failed:
	clc
	rts

;;; Earlier parameters have already been restored by the caller. The final one is
;;; still in the natural call registers, so copy it to its allocated parameter
;;; slot once here. Zero-argument functions need no entry store.
emit_function_final_parameter_store:
	ldx callEmitCallee
	lda persistentParamCount,x
	beq .done
	sec
	sbc #$01
	sta callEmitArgument
	lda persistentParamStart,x
	clc
	adc callEmitArgument
	tax
	lda parameterType,x
	sta callEmitParamType
	jsr emit_store_call_registers_to_callee
	rts
.done:
	sec
	rts

emit_current_symbol:
	jsr emit_current_name
	bcc .failed
	jmp emit_program_bss_assignment
.failed:
	clc
	rts

emit_static_byte:
	sta programStaticByte
	ldx #<programBytePrefix
	ldy #>programBytePrefix
	jsr emit_string
	bcc .failed
	lda programStaticByte
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; Runtime-private storage is allocated before the final BSS size is emitted.
;;; Deferred string bytes follow afterwards and therefore remain loaded data.
emit_bss_boundaries:
	jsr emit_runtime_support
	bcc .failed
	ldx #<programBssEndPrefix
	ldy #>programBssEndPrefix
	jsr emit_string
	bcc .failed
	lda bssOffset
	sta emitWord
	lda bssOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_program_bss_assignment:
	ldx #<runtimeBssAssign
	ldy #>runtimeBssAssign
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

programBytePrefix:	byte $09,'b','y','t','e',' ','$',0
programBssEndPrefix:	byte '_','_','n','c','_','b','s','s','_','e','n','d',' ','=',' ','N','C','_','B','S','S','+','$',0

;;; One-byte formatter scratch; emit_static_byte assigns it before use.
programStaticByte = $b3fe
