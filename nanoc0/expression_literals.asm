;;; ---------------------------------------------------------------------------
;;; Deferred string literals
;;; ---------------------------------------------------------------------------

capture_string_literal:
	lda literalCount
	cmp #EXPR_LITERAL_CAPACITY
	bcc .countOk
	lda #EXPR_LITERAL_COUNT_OVERFLOW
	jmp expression_fail
.countOk:
	sta currentLiteralIndex
	asl
	tax
	lda literalBytesUsed
	sta literalOffset,x
	lda literalBytesUsed+1
	sta literalOffset+1,x
	lda currentTokenLength
	sta literalLength,x
	lda #$00
	sta literalLength+1,x

	clc
	lda literalBytesUsed
	adc currentTokenLength
	sta literalNewEnd
	lda literalBytesUsed+1
	adc #$00
	sta literalNewEnd+1
	inc literalNewEnd
	bne .capacity
	inc literalNewEnd+1
.capacity:
	lda literalNewEnd+1
	cmp #>EXPR_LITERAL_BYTES
	bcc .fits
	bne .tooMany
	lda literalNewEnd
	cmp #<EXPR_LITERAL_BYTES
	bcc .fits
	beq .fits
.tooMany:
	lda #EXPR_LITERAL_POOL_OVERFLOW
	jmp expression_fail
.fits:
	clc
	lda #<literalBytes
	adc literalBytesUsed
	sta EMIT_PTR
	lda #>literalBytes
	adc literalBytesUsed+1
	sta EMIT_PTR+1
	ldy #$00
.copy:
	cpy currentTokenLength
	beq .nul
	lda currentTokenText,y
	sta (EMIT_PTR),y
	iny
	jmp .copy
.nul:
	lda #$00
	sta (EMIT_PTR),y
	lda literalNewEnd
	sta literalBytesUsed
	lda literalNewEnd+1
	sta literalBytesUsed+1
	inc literalCount
	sec
	rts

;;; emit_deferred_literals
;;; Called after executable/runtime output. Each literal is a label followed by
;;; ordinary byte directives. Rows are deliberately capped at 16 values so the
;;; generated source always stays well inside ass's 255-byte line buffer.
emit_deferred_literals:
	lda #$00
	sta literalEmitIndex
.loop:
	lda literalEmitIndex
	cmp literalCount
	beq .done
	jsr emit_one_literal
	bcs .emitted
	rts
.emitted:
	inc literalEmitIndex
	jmp .loop
.done:
	sec
	rts

emit_one_literal:
	lda literalEmitIndex
	jsr emit_literal_name
	bcs .colon
	rts
.colon:
	lda #':'
	jsr emit_output_byte
	bcs .labelDone
	rts
.labelDone:
	jsr emit_newline
	bcs .prepare
	rts
.prepare:
	lda literalEmitIndex
	asl
	tax
	lda literalOffset,x
	sta literalEmitOffset
	lda literalOffset+1,x
	sta literalEmitOffset+1
	lda literalLength,x
	sta literalEmitRemaining
	inc literalEmitRemaining		; include NUL; scanner text < 255 bytes
	lda #$00
	sta literalEmitColumn

.bytes:
	lda literalEmitRemaining
	beq .done
	lda literalEmitColumn
	bne .comma
	ldx #<exprBytePrefix
	ldy #>exprBytePrefix
	jsr emit_string
	bcs .bytePrefixDone
	rts
.bytePrefixDone:
	jmp .byte
.comma:
	lda #','
	jsr emit_output_byte
	bcs .byte
	rts
.byte:
	lda #'$'
	jsr emit_output_byte
	bcs .byteAddress
	rts
.byteAddress:
	clc
	lda #<literalBytes
	adc literalEmitOffset
	sta EMIT_PTR
	lda #>literalBytes
	adc literalEmitOffset+1
	sta EMIT_PTR+1
	ldy #$00
	lda (EMIT_PTR),y
	jsr emit_hex_byte
	bcs .byteDone
	rts
.byteDone:
	inc literalEmitOffset
	bne .offsetOk
	inc literalEmitOffset+1
.offsetOk:
	inc literalEmitColumn
	dec literalEmitRemaining
	lda literalEmitRemaining
	beq .endRow
	lda literalEmitColumn
	cmp #EXPR_LITERAL_ROW
	bne .bytes
.endRow:
	jsr emit_newline
	bcs .rowDone
	rts
.rowDone:
	lda #$00
	sta literalEmitColumn
	lda literalEmitRemaining
	bne .bytes
.done:
	sec
	rts


