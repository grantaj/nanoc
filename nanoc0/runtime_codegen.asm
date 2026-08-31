;;; runtime_codegen.asm
;;;
;;; Final generated-program support for Nano C Phase 1.
;;;
;;; The compiler driver calls emit_runtime_support from its final BSS-boundary
;;; hook, after all C functions have been parsed but before __nc_bss_end is
;;; emitted. At that point caller staging, runtime parameter slots and all source
;;; storage are known.
;;;
;;; Runtime state is deliberately tiny and visible:
;;;
;;;   six handles: five nested bootstrap input files plus one simultaneous output;
;;;   one mode byte and one EOF-pending byte per handle;
;;;   one scratch handle byte;
;;;   one 256-byte filename buffer only when io_create is used.
;;;
;;; C-visible handles are just indices 0..5. KERNAL LFNs are 4+handle. Reads use
;;; device 8 and writes use device 9. There is no stream object, descriptor table
;;; structure, generic device layer or software C stack.
;;;
;;; __nc_init clears the complete generated BSS interval. Only source globals
;;; require C zero-initialisation, but clearing parameter/spill/staging storage as
;;; well costs startup cycles rather than compiler machinery and preserves one
;;; authoritative BSS boundary.
;;;
;;; Runtime/support entry points clear decimal mode before doing any arithmetic
;;; and again on return. Generated Nano C never emits SED, but this makes the
;;; machine invariant explicit even when a support routine is called with D set.
;;;
;;; Runtime routines are emitted only when source used them. __nc_mul16 is kept in
;;; the small support slab unconditionally: #55 already emits calls to that fixed
;;; helper, and one always-present few-dozen-byte routine is simpler than another
;;; compiler usage bit solely to omit dead support text.

RUNTIME_HANDLE_CAPACITY = 6

emit_runtime_support:
	jsr prepare_runtime_storage
	bcs .storageReady
	rts
.storageReady:
	jsr emit_runtime_init
	bcs .initDone
	rts
.initDone:
	ldx #<runtimeMulText
	ldy #>runtimeMulText
	jsr emit_runtime_lines
	bcs .mulDone
	rts
.mulDone:
	jsr runtime_any_used
	bcs .runtime
	sec
	rts
.runtime:
	ldx #<runtimeCommonText
	ldy #>runtimeCommonText
	jsr emit_runtime_lines
	bcs .commonDone
	rts
.commonDone:
	lda runtimeUsed
	beq .read
	ldx #<runtimeOpenText
	ldy #>runtimeOpenText
	jsr emit_runtime_lines
	bcc .failed
.read:
	lda runtimeUsed+1
	beq .create
	ldx #<runtimeReadText
	ldy #>runtimeReadText
	jsr emit_runtime_lines
	bcc .failed
.create:
	lda runtimeUsed+2
	beq .write
	ldx #<runtimeCreateText
	ldy #>runtimeCreateText
	jsr emit_runtime_lines
	bcc .failed
.write:
	lda runtimeUsed+3
	beq .close
	ldx #<runtimeWriteText
	ldy #>runtimeWriteText
	jsr emit_runtime_lines
	bcc .failed
.close:
	lda runtimeUsed+4
	beq .done
	ldx #<runtimeCloseText
	ldy #>runtimeCloseText
	jsr emit_runtime_lines
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

runtime_any_used:
	ldx #$00
.loop:
	lda runtimeUsed,x
	bne .yes
	inx
	cpx #RUNTIME_SYMBOL_COUNT
	bne .loop
	clc
	rts
.yes:
	sec
	rts

;;; Runtime-private BSS is allocated after C function storage. The final caller
;;; then emits __nc_bss_end from the updated bssOffset.
prepare_runtime_storage:
	jsr runtime_any_used
	bcs .needed
	sec
	rts
.needed:
	lda #RUNTIME_HANDLE_CAPACITY
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	lda #runtimeModeNameEnd-runtimeModeName
	ldx #<runtimeModeName
	ldy #>runtimeModeName
	jsr emit_runtime_definition
	bcc .failed

	lda #RUNTIME_HANDLE_CAPACITY
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	lda #runtimeEofNameEnd-runtimeEofName
	ldx #<runtimeEofName
	ldy #>runtimeEofName
	jsr emit_runtime_definition
	bcc .failed

	lda #$01
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	lda #runtimeHandleNameEnd-runtimeHandleName
	ldx #<runtimeHandleName
	ldy #>runtimeHandleName
	jsr emit_runtime_definition
	bcc .failed

	lda runtimeUsed+2
	beq .done
	lda #$00
	sta allocSize
	lda #$01
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	lda #runtimeNameBufferNameEnd-runtimeNameBufferName
	ldx #<runtimeNameBufferName
	ldy #>runtimeNameBufferName
	jsr emit_runtime_definition
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

;;; A=generated symbol-name length, X/Y=address. allocOffset is the allocation
;;; just committed.
emit_runtime_definition:
	jsr emit_text
	bcc .failed
	lda #runtimeBssAssignEnd-runtimeBssAssign
	ldx #<runtimeBssAssign
	ldy #>runtimeBssAssign
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

;;; bssOffset is final after prepare_runtime_storage. Emit its low/high bytes
;;; directly into the count loaded by __nc_init.
emit_runtime_init:
	ldx #<runtimeInitPrefix
	ldy #>runtimeInitPrefix
	jsr emit_runtime_lines
	bcc .failed
	lda #runtimeLdaImmediateEnd-runtimeLdaImmediate
	ldx #<runtimeLdaImmediate
	ldy #>runtimeLdaImmediate
	jsr emit_text
	bcc .failed
	lda bssOffset
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #runtimeStaTmpEnd-runtimeStaTmp
	ldx #<runtimeStaTmp
	ldy #>runtimeStaTmp
	jsr emit_text
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #runtimeLdaImmediateEnd-runtimeLdaImmediate
	ldx #<runtimeLdaImmediate
	ldy #>runtimeLdaImmediate
	jsr emit_text
	bcc .failed
	lda bssOffset+1
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	lda #runtimeStaTmpHighEnd-runtimeStaTmpHigh
	ldx #<runtimeStaTmpHigh
	ldy #>runtimeStaTmpHigh
	jsr emit_text
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<runtimeInitSuffix
	ldy #>runtimeInitSuffix
	jmp emit_runtime_lines
.failed:
	clc
	rts

;;; A runtime text slab is stored as consecutive `string` lines. Both vasm
;;; oldstyle and ass terminate `string` with NUL. One extra zero after the slab
;;; gives a double-NUL end marker. Turning the first NUL into a newline lets the
;;; source below remain readable assembly instead of a character-byte dump.
emit_runtime_lines:
	stx EMIT_PTR
	sty EMIT_PTR+1
.loop:
	ldy #$00
	lda (EMIT_PTR),y
	beq .lineEnd
	jsr emit_output_byte
	bcc .failed
	inc EMIT_PTR
	bne .loop
	inc EMIT_PTR+1
	jmp .loop
.lineEnd:
	lda #$0a
	jsr emit_output_byte
	bcc .failed
	inc EMIT_PTR
	bne .peek
	inc EMIT_PTR+1
.peek:
	ldy #$00
	lda (EMIT_PTR),y
	bne .loop
	sec
	rts
.failed:
	clc
	rts

runtimeModeName:	byte '_','_','n','c','_','i','o','_','m','o','d','e'
runtimeModeNameEnd:
runtimeEofName:		byte '_','_','n','c','_','i','o','_','e','o','f'
runtimeEofNameEnd:
runtimeHandleName:	byte '_','_','n','c','_','i','o','_','h','a','n','d','l','e'
runtimeHandleNameEnd:
runtimeNameBufferName:	byte '_','_','n','c','_','i','o','_','n','a','m','e'
runtimeNameBufferNameEnd:
runtimeBssAssign:	byte ' ','=',' ','N','C','_','B','S','S','+','$'
runtimeBssAssignEnd:
runtimeLdaImmediate:	byte $09,'l','d','a',' ','#','$'
runtimeLdaImmediateEnd:
runtimeStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P'
runtimeStaTmpEnd:
runtimeStaTmpHigh:	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1'
runtimeStaTmpHighEnd:

runtimeInitPrefix:
	string "__nc_init:"
	string "    cld"
	string "    lda #<NC_BSS"
	string "    sta NC_PTR"
	string "    lda #>NC_BSS"
	string "    sta NC_PTR+1"
	byte 0

runtimeInitSuffix:
	string "    ldy #$00"
	string "__nc_init_loop:"
	string "    lda NC_TMP"
	string "    ora NC_TMP+1"
	string "    beq __nc_init_done"
	string "    lda #$00"
	string "    sta (NC_PTR),y"
	string "    inc NC_PTR"
	string "    bne __nc_init_pointer_done"
	string "    inc NC_PTR+1"
	string "__nc_init_pointer_done:"
	string "    lda NC_TMP"
	string "    bne __nc_init_decrement_low"
	string "    dec NC_TMP+1"
	string "__nc_init_decrement_low:"
	string "    dec NC_TMP"
	string "    jmp __nc_init_loop"
	string "__nc_init_done:"
	string "    cld"
	string "    rts"
	byte 0

;;; left operand in NC_TMP, right in A/X, low 16-bit product back in A/X.
runtimeMulText:
	string "__nc_mul16:"
	string "    cld"
	string "    sta NC_PTR"
	string "    stx NC_PTR+1"
	string "    ldy #$00"
	string "    ldx #$00"
	string "__nc_mul16_loop:"
	string "    lda NC_PTR"
	string "    ora NC_PTR+1"
	string "    beq __nc_mul16_done"
	string "    lda NC_PTR"
	string "    and #$01"
	string "    beq __nc_mul16_noadd"
	string "    tya"
	string "    clc"
	string "    adc NC_TMP"
	string "    tay"
	string "    txa"
	string "    adc NC_TMP+1"
	string "    tax"
	string "__nc_mul16_noadd:"
	string "    asl NC_TMP"
	string "    rol NC_TMP+1"
	string "    lsr NC_PTR+1"
	string "    ror NC_PTR"
	string "    jmp __nc_mul16_loop"
	string "__nc_mul16_done:"
	string "    tya"
	string "    cld"
	string "    rts"
	byte 0

runtimeCommonText:
	string "__nc_io_zero:"
	string "    lda #$00"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	string "__nc_io_minus1:"
	string "    lda #$ff"
	string "    ldx #$ff"
	string "    cld"
	string "    rts"
	string "__nc_io_minus2:"
	string "    lda #$fe"
	string "    ldx #$ff"
	string "    cld"
	string "    rts"
	byte 0

runtimeOpenText:
	string "__c_io_open:"
	string "    cld"
	string "    ldx #$00"
	string "__nc_io_open_find:"
	string "    lda __nc_io_mode,x"
	string "    beq __nc_io_open_slot"
	string "    inx"
	string "    cpx #$06"
	string "    bne __nc_io_open_find"
	string "    jmp __nc_io_minus1"
	string "__nc_io_open_slot:"
	string "    stx __nc_io_handle"
	string "    lda __c_io_open__v01+1"
	string "    beq __nc_io_open_length_ok"
	string "    jmp __nc_io_minus1"
	string "__nc_io_open_length_ok:"
	string "    jsr $ffcc"
	string "    lda __c_io_open__v01"
	string "    ldx __c_io_open__v00"
	string "    ldy __c_io_open__v00+1"
	string "    jsr $ffbd"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    tay"
	string "    ldx #$08"
	string "    jsr $ffba"
	string "    jsr $ffc0"
	string "    bcc __nc_io_open_ok"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    jsr $ffc3"
	string "    jmp __nc_io_minus1"
	string "__nc_io_open_ok:"
	string "    ldx __nc_io_handle"
	string "    lda #$01"
	string "    sta __nc_io_mode,x"
	string "    lda #$00"
	string "    sta __nc_io_eof,x"
	string "    txa"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	byte 0

runtimeReadText:
	string "__c_io_read:"
	string "    cld"
	string "    lda __c_io_read__v00+1"
	string "    beq __nc_io_read_handle_low"
	string "    jmp __nc_io_minus2"
	string "__nc_io_read_handle_low:"
	string "    lda __c_io_read__v00"
	string "    cmp #$06"
	string "    bcc __nc_io_read_in_range"
	string "    jmp __nc_io_minus2"
	string "__nc_io_read_in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    cmp #$01"
	string "    beq __nc_io_read_open"
	string "    jmp __nc_io_minus2"
	string "__nc_io_read_open:"
	string "    lda __nc_io_eof,x"
	string "    beq __nc_io_read_byte"
	string "    jmp __nc_io_minus1"
	string "__nc_io_read_byte:"
	string "    jsr $ffcc"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    tax"
	string "    jsr $ffc6"
	string "    bcc __nc_io_read_selected"
	string "    jmp __nc_io_read_error_clear"
	string "__nc_io_read_selected:"
	string "    jsr $ffcf"
	string "    sta NC_TMP"
	string "    jsr $ffb7"
	string "    sta NC_TMP+1"
	string "    jsr $ffcc"
	string "    lda NC_TMP+1"
	string "    and #$bf"
	string "    beq __nc_io_read_status_ok"
	string "    jmp __nc_io_minus2"
	string "__nc_io_read_status_ok:"
	string "    lda NC_TMP+1"
	string "    and #$40"
	string "    beq __nc_io_read_return"
	string "    ldx __nc_io_handle"
	string "    lda #$01"
	string "    sta __nc_io_eof,x"
	string "__nc_io_read_return:"
	string "    lda NC_TMP"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	string "__nc_io_read_error_clear:"
	string "    jsr $ffcc"
	string "    jmp __nc_io_minus2"
	byte 0

runtimeCreateText:
	string "__c_io_create:"
	string "    cld"
	string "    ldx #$00"
	string "__nc_io_create_find:"
	string "    lda __nc_io_mode,x"
	string "    beq __nc_io_create_slot"
	string "    inx"
	string "    cpx #$06"
	string "    bne __nc_io_create_find"
	string "    jmp __nc_io_minus1"
	string "__nc_io_create_slot:"
	string "    stx __nc_io_handle"
	string "    lda __c_io_create__v01+1"
	string "    beq __nc_io_create_length_low"
	string "    jmp __nc_io_minus1"
	string "__nc_io_create_length_low:"
	string "    lda __c_io_create__v01"
	string "    cmp #$f9"
	string "    bcc __nc_io_create_length_ok"
	string "    jmp __nc_io_minus1"
	string "__nc_io_create_length_ok:"
	string "    lda #'@'"
	string "    sta __nc_io_name"
	string "    lda #'0'"
	string "    sta __nc_io_name+1"
	string "    lda #':'"
	string "    sta __nc_io_name+2"
	string "    lda __c_io_create__v00"
	string "    sta NC_PTR"
	string "    lda __c_io_create__v00+1"
	string "    sta NC_PTR+1"
	string "    ldy #$00"
	string "__nc_io_create_copy:"
	string "    cpy __c_io_create__v01"
	string "    beq __nc_io_create_suffix"
	string "    lda (NC_PTR),y"
	string "    sta __nc_io_name+3,y"
	string "    iny"
	string "    jmp __nc_io_create_copy"
	string "__nc_io_create_suffix:"
	string "    tya"
	string "    clc"
	string "    adc #$03"
	string "    tax"
	string "    lda #','"
	string "    sta __nc_io_name,x"
	string "    inx"
	string "    lda #'S'"
	string "    sta __nc_io_name,x"
	string "    inx"
	string "    lda #','"
	string "    sta __nc_io_name,x"
	string "    inx"
	string "    lda #'W'"
	string "    sta __nc_io_name,x"
	string "    jsr $ffcc"
	string "    lda __c_io_create__v01"
	string "    clc"
	string "    adc #$07"
	string "    ldx #<__nc_io_name"
	string "    ldy #>__nc_io_name"
	string "    jsr $ffbd"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    tay"
	string "    ldx #$09"
	string "    jsr $ffba"
	string "    jsr $ffc0"
	string "    bcc __nc_io_create_ok"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    jsr $ffc3"
	string "    jmp __nc_io_minus1"
	string "__nc_io_create_ok:"
	string "    ldx __nc_io_handle"
	string "    lda #$02"
	string "    sta __nc_io_mode,x"
	string "    lda #$00"
	string "    sta __nc_io_eof,x"
	string "    txa"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	byte 0

runtimeWriteText:
	string "__c_io_write:"
	string "    cld"
	string "    lda __c_io_write__v00+1"
	string "    beq __nc_io_write_handle_low"
	string "    jmp __nc_io_minus1"
	string "__nc_io_write_handle_low:"
	string "    lda __c_io_write__v00"
	string "    cmp #$06"
	string "    bcc __nc_io_write_in_range"
	string "    jmp __nc_io_minus1"
	string "__nc_io_write_in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    cmp #$02"
	string "    beq __nc_io_write_open"
	string "    jmp __nc_io_minus1"
	string "__nc_io_write_open:"
	string "    jsr $ffcc"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    tax"
	string "    jsr $ffc9"
	string "    bcc __nc_io_write_selected"
	string "    jmp __nc_io_write_error_clear"
	string "__nc_io_write_selected:"
	string "    lda __c_io_write__v01"
	string "    jsr $ffd2"
	string "    jsr $ffb7"
	string "    sta NC_TMP"
	string "    jsr $ffcc"
	string "    lda NC_TMP"
	string "    beq __nc_io_write_ok"
	string "    jmp __nc_io_minus1"
	string "__nc_io_write_ok:"
	string "    jmp __nc_io_zero"
	string "__nc_io_write_error_clear:"
	string "    jsr $ffcc"
	string "    jmp __nc_io_minus1"
	byte 0

runtimeCloseText:
	string "__c_io_close:"
	string "    cld"
	string "    lda __c_io_close__v00+1"
	string "    beq __nc_io_close_handle_low"
	string "    jmp __nc_io_minus1"
	string "__nc_io_close_handle_low:"
	string "    lda __c_io_close__v00"
	string "    cmp #$06"
	string "    bcc __nc_io_close_in_range"
	string "    jmp __nc_io_minus1"
	string "__nc_io_close_in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    bne __nc_io_close_open"
	string "    jmp __nc_io_minus1"
	string "__nc_io_close_open:"
	string "    jsr $ffcc"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #$04"
	string "    jsr $ffc3"
	string "    ldx __nc_io_handle"
	string "    lda #$00"
	string "    sta __nc_io_mode,x"
	string "    sta __nc_io_eof,x"
	string "    jmp __nc_io_zero"
	byte 0
