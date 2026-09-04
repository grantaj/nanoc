;;; program_output.asm
;;;
;;; Concrete `ass` text emitted by the production nanoc0 driver.
;;;
;;; Declarations call four tiny hooks as storage facts become known. This file
;;; spells those facts directly as readable assembler source; it is not an
;;; intermediate representation and retains no copy of the generated program.

emit_persistent_symbol:
	cmp #EMIT_STORAGE_BSS
	beq .bss

	;;; Data and functions are ordinary loaded text with a global label. CMP/branches
	;;; leave X holding the symbol index supplied by the declaration parser.
.label:
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline

.bss:
	jsr emit_persistent_name
	bcc .failed
	jmp emit_program_bss_assignment
.failed:
	clc
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

programStaticByte:	byte 0
