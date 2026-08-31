;;; emit.asm
;;;
;;; Tiny text formatter shared by Nano C code generators.
;;;
;;; Generated `ass` source is streamed one byte at a time. When
;;; emitOutputEnabled is zero the sink discards text (useful while declaration-
;;; only tests exercise parser state). When enabled, bytes go straight to the
;;; compiler's fixed KERNAL output logical file. There is no line/output buffer.
;;;
;;; The bootstrap driver opens source on device 8 and generated output on device
;;; 9. Both drives still share the C64's one IEC bus, so source.asm records the
;;; currently selected TALK/LISTEN direction. On a real direction change we
;;; CLRCHN first, then CHKOUT the still-open output logical file; steady output
;;; remains a simple stream of CHROUT calls.
;;;
;;; emit_output_byte preserves X, Y and both compiler scratch pairs because the
;;; formatter may be walking text through them. #57 only needs to add the normal
;;; create/open/close wrapper around this already-streaming byte path.
;;;
;;; Generated storage names are deliberately derived only from persistent facts:
;;;
;;;   global/function       __c_<source-name>
;;;   parameter/local       __c_<function-name>__vNN
;;;   expression spill      __c_<function-name>__sNN
;;;   deferred string       __nc_stringNN
;;;   compiler label        __nc_LNNNN
;;;
;;; In particular, parameter slot names use the parameter ordinal/current-table
;;; index rather than the source parameter name. The current table is discarded
;;; after a function, so #57 can later reconstruct a callee parameter slot from
;;; exactly the metadata #54 retained: function identity plus argument ordinal.
;;;
;;; This file formats only the few things the compiler repeatedly needs. It is
;;; not printf and it is not an output representation.

EMIT_PTR        = $fc
EMIT_OUTPUT_LFN = 3

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

	lda compilerIecDirection
	cmp #COMPILER_IO_OUTPUT
	beq .selected
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	ldx #EMIT_OUTPUT_LFN
	jsr CHKOUT
	bcs .channelFailed
	lda #COMPILER_IO_OUTPUT
	sta compilerIecDirection
.selected:
	lda emitOutputByte
	jsr CHROUT
	jsr READST
	sta emitOutputStatus
	jmp .restore
.channelFailed:
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda #$ff
	sta emitOutputStatus

.restore:
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

;;; X=persistent symbol index. Emit only its source spelling, with no generated
;;; namespace prefix. Current/spill names use this as their function component.
emit_persistent_source_name:
	lda persistentNameOffsetLo,x
	sta nameCompareOffset
	lda persistentNameOffsetHi,x
	sta nameCompareOffset+1
	jmp emit_pool_name

;;; X=persistent symbol index -> __c_<source-name>.
emit_persistent_name:
	stx emitSavedIndex
	lda #emitCPrefixEnd-emitCPrefix
	ldx #<emitCPrefix
	ldy #>emitCPrefix
	jsr emit_text
	bcc .failed
	ldx emitSavedIndex
	jsr emit_persistent_source_name
	ldx emitSavedIndex
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

;;; X=current-function symbol index -> __c_<function-name>__vNN.
;;; Parameters occupy current indices 0..parameter-count-1, so this spelling is
;;; reconstructable by later callers without retaining parameter source names.
emit_current_name:
	stx emitSavedIndex
	lda #emitCPrefixEnd-emitCPrefix
	ldx #<emitCPrefix
	ldy #>emitCPrefix
	jsr emit_text
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	lda #emitValueSuffixEnd-emitValueSuffix
	ldx #<emitValueSuffix
	ldy #>emitValueSuffix
	jsr emit_text
	bcc .failed
	lda emitSavedIndex
	jsr emit_hex_byte
	ldx emitSavedIndex
	rts
.failed:
	ldx emitSavedIndex
	clc
	rts

;;; A=spill depth -> __c_<function-name>__sNN.
emit_spill_name:
	sta emitSavedValue
	lda #emitCPrefixEnd-emitCPrefix
	ldx #<emitCPrefix
	ldy #>emitCPrefix
	jsr emit_text
	bcc .failed
	ldx currentFunctionIndex
	jsr emit_persistent_source_name
	bcc .failed
	lda #emitSpillSuffixEnd-emitSpillSuffix
	ldx #<emitSpillSuffix
	ldy #>emitSpillSuffix
	jsr emit_text
	bcc .failed
	lda emitSavedValue
	jmp emit_hex_byte
.failed:
	clc
	rts

;;; A=literal index -> __nc_stringNN.
emit_literal_name:
	sta emitSavedValue
	lda #emitStringPrefixEnd-emitStringPrefix
	ldx #<emitStringPrefix
	ldy #>emitStringPrefix
	jsr emit_text
	bcc .failed
	lda emitSavedValue
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

emitCPrefix:		byte '_','_','c','_'
emitCPrefixEnd:
emitValueSuffix:	byte '_','_','v'
emitValueSuffixEnd:
emitSpillSuffix:	byte '_','_','s'
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
emitSavedValue:		byte 0
emitWord:		word 0
generatedLabelCounter:	word 0
emitLabelValue:		word 0
