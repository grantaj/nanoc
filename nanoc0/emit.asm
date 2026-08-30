;;; emit.asm
;;;
;;; Tiny text formatter shared by Nano C code generators.
;;;
;;; Generated `ass` source is streamed one byte at a time. When
;;; emitOutputEnabled is zero the sink discards text (useful while declaration-
;;; only tests exercise parser state). When enabled, the caller must already
;;; have selected a KERNAL output channel with CHKOUT and bytes go straight to
;;; CHROUT. There is no line/output buffer.
;;;
;;; emit_output_byte preserves X, Y and both compiler scratch pairs because the
;;; formatter may be walking text through them. #57 only needs to add the normal
;;; create/open/close wrapper around this already-streaming byte path.
;;;
;;; This file deliberately formats only the few things the compiler repeatedly
;;; needs: fixed fragments, hexadecimal values, source names and generated
;;; storage/label names. It is not printf.

EMIT_PTR = $fc

;;; emit_output_byte
;;; A=byte. Carry set success. X/Y and $fc-$ff preserved.
emit_output_byte:
	sta emitOutputByte
	lda emitOutputEnabled
	bne .write
	sec
	rts
.write:
	stx emitOutputSavedX
	sty emitOutputSavedY
	lda $fc
	sta emitOutputSavedScratch
	lda $fd
	sta emitOutputSavedScratch+1
	lda $fe
	sta emitOutputSavedScratch+2
	lda $ff
	sta emitOutputSavedScratch+3
	lda emitOutputByte
	jsr CHROUT
	jsr READST
	sta emitOutputStatus
	lda emitOutputSavedScratch
	sta $fc
	lda emitOutputSavedScratch+1
	sta $fd
	lda emitOutputSavedScratch+2
	sta $fe
	lda emitOutputSavedScratch+3
	sta $ff
	ldx emitOutputSavedX
	ldy emitOutputSavedY
	lda emitOutputStatus
	beq .ok
	clc
	rts
.ok:
	sec
	rts

;;; emit_text
;;; A=length, X/Y=address. Carry set when all bytes were accepted.
emit_text:
	sta emitTextLength
	stx EMIT_PTR
	sty EMIT_PTR+1
	ldy #$00
.loop:
	cpy emitTextLength
	beq .done
	lda (EMIT_PTR),y
	jsr emit_output_byte
	bcc .failed
	iny
	jmp .loop
.done:
	sec
.failed:
	rts

emit_newline:
	lda #$0a
	jmp emit_output_byte

;;; emit_hex_nibble
;;; A low nibble -> one uppercase hexadecimal digit.
emit_hex_nibble:
	and #$0f
	cmp #10
	bcc .digit
	clc
	adc #'A'-10
	jmp emit_output_byte
.digit:
	clc
	adc #'0'
	jmp emit_output_byte

;;; emit_hex_byte
;;; A -> exactly two hexadecimal digits, no '$'.
emit_hex_byte:
	sta emitNumber
	lsr
	lsr
	lsr
	lsr
	jsr emit_hex_nibble
	bcc .failed
	lda emitNumber
	jsr emit_hex_nibble
.failed:
	rts

;;; emit_hex_word
;;; emitWord -> exactly four hexadecimal digits, high byte first.
emit_hex_word:
	lda emitWord+1
	jsr emit_hex_byte
	bcc .failed
	lda emitWord
	jsr emit_hex_byte
.failed:
	rts

;;; emit_pool_name
;;; nameCompareOffset points to one [length][bytes...] owned name.
emit_pool_name:
	clc
	lda #<namePool
	adc nameCompareOffset
	sta EMIT_PTR
	lda #>namePool
	adc nameCompareOffset+1
	sta EMIT_PTR+1
	ldy #$00
	lda (EMIT_PTR),y
	sta emitTextLength
	inc EMIT_PTR
	bne .start
	inc EMIT_PTR+1
.start:
	ldy #$00
.loop:
	cpy emitTextLength
	beq .done
	lda (EMIT_PTR),y
	jsr emit_output_byte
	bcc .failed
	iny
	jmp .loop
.done:
	sec
.failed:
	rts

;;; Persistent globals/functions retain their source spelling directly.
emit_persistent_name:
	lda persistentNameOffsetLo,x
	sta nameCompareOffset
	lda persistentNameOffsetHi,x
	sta nameCompareOffset+1
	jmp emit_pool_name

;;; Current-function storage is qualified by the owning function identity so
;;; shadowing never creates an assembler-name collision:
;;;     __f12_local
emit_current_name:
	stx emitSavedIndex
	lda #emitFunctionPrefixEnd-emitFunctionPrefix
	ldx #<emitFunctionPrefix
	ldy #>emitFunctionPrefix
	jsr emit_text
	bcc .failed
	lda currentFunctionIndex
	jsr emit_hex_byte
	bcc .failed
	lda #'_'
	jsr emit_output_byte
	bcc .failed
	ldx emitSavedIndex
	lda currentNameOffsetLo,x
	sta nameCompareOffset
	lda currentNameOffsetHi,x
	sta nameCompareOffset+1
	jsr emit_pool_name
	ldx emitSavedIndex
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

;;; Compiler spill names are deterministic from function + spill depth:
;;;     __f12_spill03
;;; A=spill depth.
emit_spill_name:
	sta emitSavedIndex
	lda #emitFunctionPrefixEnd-emitFunctionPrefix
	ldx #<emitFunctionPrefix
	ldy #>emitFunctionPrefix
	jsr emit_text
	bcc .failed
	lda currentFunctionIndex
	jsr emit_hex_byte
	bcc .failed
	lda #emitSpillSuffixEnd-emitSpillSuffix
	ldx #<emitSpillSuffix
	ldy #>emitSpillSuffix
	jsr emit_text
	bcc .failed
	lda emitSavedIndex
	jmp emit_hex_byte
.failed:
	clc
	rts

;;; Deferred strings have one simple generated namespace:
;;;     __nc_string03
;;; A=literal index.
emit_literal_name:
	sta emitSavedIndex
	lda #emitStringPrefixEnd-emitStringPrefix
	ldx #<emitStringPrefix
	ldy #>emitStringPrefix
	jsr emit_text
	bcc .failed
	lda emitSavedIndex
	jmp emit_hex_byte
.failed:
	clc
	rts

;;; Generated control labels are monotonically numbered and never patched.
;;; emitLabelValue is the label to spell.
emit_generated_label_name:
	lda #emitLabelPrefixEnd-emitLabelPrefix
	ldx #<emitLabelPrefix
	ldy #>emitLabelPrefix
	jsr emit_text
	bcc .failed
	lda emitLabelValue
	sta emitWord
	lda emitLabelValue+1
	sta emitWord+1
	jmp emit_hex_word
.failed:
	clc
	rts

;;; reserve_generated_label
;;; Copy the current counter into emitLabelValue, then increment it.
reserve_generated_label:
	lda generatedLabelCounter
	sta emitLabelValue
	lda generatedLabelCounter+1
	sta emitLabelValue+1
	inc generatedLabelCounter
	bne .done
	inc generatedLabelCounter+1
.done:
	rts

reset_generated_labels:
	lda #$00
	sta generatedLabelCounter
	sta generatedLabelCounter+1
	rts

emitFunctionPrefix:	byte '_','_','f'
emitFunctionPrefixEnd:
emitSpillSuffix:	byte '_','s','p','i','l','l'
emitSpillSuffixEnd:
emitStringPrefix:	byte '_','_','n','c','_','s','t','r','i','n','g'
emitStringPrefixEnd:
emitLabelPrefix:	byte '_','_','n','c','_','L'
emitLabelPrefixEnd:

emitOutputEnabled:	byte 0
emitOutputByte:		byte 0
emitOutputSavedX:	byte 0
emitOutputSavedY:	byte 0
emitOutputSavedScratch:	ds 4
emitOutputStatus:	byte 0
emitTextLength:		byte 0
emitNumber:		byte 0
emitSavedIndex:		byte 0
emitWord:		word 0
generatedLabelCounter:	word 0
emitLabelValue:		word 0
