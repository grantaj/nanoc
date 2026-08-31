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
;;;   one mode byte and one EOF/prefetch byte per handle;
;;;   one scratch handle byte;
;;;   one 256-byte filename buffer only when io_create is used.
;;;
;;; C-visible handles are just indices 0..5. KERNAL LFNs are 4+handle. Reads use
;;; device 8 and writes use device 9. There is no stream object, descriptor table
;;; structure, generic device layer or software C stack.
;;;
;;; Input OPEN on an IEC disk does not itself report a missing file. io_open must
;;; therefore select the channel and read one byte before READST can distinguish
;;; a real file from a failed disk open. The two prefetch modes remember that
;;; byte in __nc_io_eof until the first io_read. No extra prefetch array exists.
;;;
;;; __nc_init clears exactly the source-global zero-required interval. Runtime
;;; mode/EOF state is then cleared explicitly when I/O support is present; normal
;;; function parameters, locals, spills and staging are never startup-cleared.
;;;
;;; Runtime/support entry points clear decimal mode before doing any arithmetic
;;; and again on return. Generated Nano C never emits SED, but this makes the
;;; machine invariant explicit even when a support routine is called with D set.
;;;
;;; Runtime routines and __nc_mul16 are emitted only when the source used them.

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
	lda multiplyUsed
	beq .runtimeCheck
	ldx #<runtimeMulText
	ldy #>runtimeMulText
	jsr emit_runtime_lines
	bcs .runtimeCheck
	rts
.runtimeCheck:
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

;;; zeroRequiredEnd is the byte count of source globals that need C startup
;;; zeroing. Runtime state, when present, is reset separately below.
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
	lda zeroRequiredEnd
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
	lda zeroRequiredEnd+1
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
	ldx #<runtimeInitClearText
	ldy #>runtimeInitClearText
	jsr emit_runtime_lines
	bcc .failed
	jsr runtime_any_used
	bcc .return
	ldx #<runtimeInitIoText
	ldy #>runtimeInitIoText
	jsr emit_runtime_lines
	bcc .failed
.return:
	ldx #<runtimeInitReturnText
	ldy #>runtimeInitReturnText
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

runtimeInitClearText:
	string "    ldy #$00"
	string ".clear_globals:"
	string "    lda NC_TMP"
	string "    ora NC_TMP+1"
	string "    beq .globals_done"
	string "    lda #$00"
	string "    sta (NC_PTR),y"
	string "    inc NC_PTR"
	string "    bne .pointer_done"
	string "    inc NC_PTR+1"
	string ".pointer_done:"
	string "    lda NC_TMP"
	string "    bne .decrement_low"
	string "    dec NC_TMP+1"
	string ".decrement_low:"
	string "    dec NC_TMP"
	string "    jmp .clear_globals"
	string ".globals_done:"
	byte 0

runtimeInitIoText:
	string "    lda #$00"
	string "    ldx #$05        ; six runtime handles"
	string ".clear_io:"
	string "    sta __nc_io_mode,x"
	string "    sta __nc_io_eof,x"
	string "    dex"
	string "    bpl .clear_io"
	byte 0

runtimeInitReturnText:
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
	string ".loop:"
	string "    lda NC_PTR"
	string "    ora NC_PTR+1"
	string "    beq .done"
	string "    lda NC_PTR"
	string "    and #$01"
	string "    beq .noadd"
	string "    tya"
	string "    clc"
	string "    adc NC_TMP"
	string "    tay"
	string "    txa"
	string "    adc NC_TMP+1"
	string "    tax"
	string ".noadd:"
	string "    asl NC_TMP"
	string "    rol NC_TMP+1"
	string "    lsr NC_PTR+1"
	string "    ror NC_PTR"
	string "    jmp .loop"
	string ".done:"
	string "    tya"
	string "    cld"
	string "    rts"
	byte 0

runtimeCommonText:
	string "NC_IO_INPUT        = $01"
	string "NC_IO_OUTPUT       = $02"
	string "NC_IO_PREFETCH     = $03"
	string "NC_IO_PREFETCH_EOF = $04"
	string "NC_IO_HANDLE_COUNT = $06"
	string "NC_IO_LFN_BASE     = $04"
	string "NC_IO_READ_DEVICE  = $08"
	string "NC_IO_WRITE_DEVICE = $09"
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
	string ".find:"
	string "    lda __nc_io_mode,x"
	string "    beq .slot"
	string "    inx"
	string "    cpx #NC_IO_HANDLE_COUNT"
	string "    bne .find"
	string "    jmp __nc_io_minus1"
	string ".slot:"
	string "    stx __nc_io_handle"
	string "    lda __c_io_open__v01+1"
	string "    beq .length_ok"
	string "    jmp __nc_io_minus1"
	string ".length_ok:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __c_io_open__v01"
	string "    ldx __c_io_open__v00"
	string "    ldy __c_io_open__v00+1"
	string "    jsr $ffbd      ; SETNAM"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    tay"
	string "    ldx #NC_IO_READ_DEVICE"
	string "    jsr $ffba      ; SETLFS"
	string "    jsr $ffc0      ; OPEN"
	string "    bcs .fail"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    tax"
	string "    jsr $ffc6      ; CHKIN"
	string "    bcs .fail"
	string "    jsr $ffcf      ; CHRIN"
	string "    sta NC_TMP"
	string "    jsr $ffb7      ; READST"
	string "    sta NC_TMP+1"
	string "    and #$bf"
	string "    beq .ok"
	string ".fail:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    jsr $ffc3      ; CLOSE"
	string "    jmp __nc_io_minus1"
	string ".ok:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    ldx __nc_io_handle"
	string "    lda NC_TMP"
	string "    sta __nc_io_eof,x"
	string "    lda NC_TMP+1"
	string "    and #$40"
	string "    beq .prefetch"
	string "    lda #NC_IO_PREFETCH_EOF"
	string "    bne .store_mode"
	string ".prefetch:"
	string "    lda #NC_IO_PREFETCH"
	string ".store_mode:"
	string "    sta __nc_io_mode,x"
	string "    txa"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	byte 0

runtimeReadText:
	string "__c_io_read:"
	string "    cld"
	string "    lda __c_io_read__v00+1"
	string "    beq .handle_low"
	string "    jmp __nc_io_minus2"
	string ".handle_low:"
	string "    lda __c_io_read__v00"
	string "    cmp #NC_IO_HANDLE_COUNT"
	string "    bcc .in_range"
	string "    jmp __nc_io_minus2"
	string ".in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    cmp #NC_IO_INPUT"
	string "    beq .open"
	string "    cmp #NC_IO_PREFETCH"
	string "    beq .prefetch"
	string "    cmp #NC_IO_PREFETCH_EOF"
	string "    beq .prefetch_eof"
	string "    jmp __nc_io_minus2"
	string ".prefetch:"
	string "    lda __nc_io_eof,x"
	string "    sta NC_TMP"
	string "    lda #$00"
	string "    sta __nc_io_eof,x"
	string "    lda #NC_IO_INPUT"
	string "    sta __nc_io_mode,x"
	string "    lda NC_TMP"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	string ".prefetch_eof:"
	string "    lda __nc_io_eof,x"
	string "    sta NC_TMP"
	string "    lda #$01"
	string "    sta __nc_io_eof,x"
	string "    lda #NC_IO_INPUT"
	string "    sta __nc_io_mode,x"
	string "    lda NC_TMP"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	string ".open:"
	string "    lda __nc_io_eof,x"
	string "    beq .byte"
	string "    jmp __nc_io_minus1"
	string ".byte:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    tax"
	string "    jsr $ffc6      ; CHKIN"
	string "    bcc .selected"
	string "    jmp .error_clear"
	string ".selected:"
	string "    jsr $ffcf      ; CHRIN"
	string "    sta NC_TMP"
	string "    jsr $ffb7      ; READST"
	string "    sta NC_TMP+1"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda NC_TMP+1"
	string "    and #$bf"
	string "    beq .status_ok"
	string "    jmp __nc_io_minus2"
	string ".status_ok:"
	string "    lda NC_TMP+1"
	string "    and #$40"
	string "    beq .return"
	string "    ldx __nc_io_handle"
	string "    lda #$01"
	string "    sta __nc_io_eof,x"
	string ".return:"
	string "    lda NC_TMP"
	string "    ldx #$00"
	string "    cld"
	string "    rts"
	string ".error_clear:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    jmp __nc_io_minus2"
	byte 0

runtimeCreateText:
	string "__c_io_create:"
	string "    cld"
	string "    ldx #$00"
	string ".find:"
	string "    lda __nc_io_mode,x"
	string "    beq .slot"
	string "    inx"
	string "    cpx #NC_IO_HANDLE_COUNT"
	string "    bne .find"
	string "    jmp __nc_io_minus1"
	string ".slot:"
	string "    stx __nc_io_handle"
	string "    lda __c_io_create__v01+1"
	string "    beq .length_low"
	string "    jmp __nc_io_minus1"
	string ".length_low:"
	string "    lda __c_io_create__v01"
	string "    cmp #$f9       ; room for @0: and ,S,W"
	string "    bcc .length_ok"
	string "    jmp __nc_io_minus1"
	string ".length_ok:"
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
	string ".copy:"
	string "    cpy __c_io_create__v01"
	string "    beq .suffix"
	string "    lda (NC_PTR),y"
	string "    sta __nc_io_name+3,y"
	string "    iny"
	string "    jmp .copy"
	string ".suffix:"
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
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __c_io_create__v01"
	string "    clc"
	string "    adc #$07"
	string "    ldx #<__nc_io_name"
	string "    ldy #>__nc_io_name"
	string "    jsr $ffbd      ; SETNAM"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    tay"
	string "    ldx #NC_IO_WRITE_DEVICE"
	string "    jsr $ffba      ; SETLFS"
	string "    jsr $ffc0      ; OPEN"
	string "    bcc .ok"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    jsr $ffc3      ; CLOSE"
	string "    jmp __nc_io_minus1"
	string ".ok:"
	string "    ldx __nc_io_handle"
	string "    lda #NC_IO_OUTPUT"
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
	string "    beq .handle_low"
	string "    jmp __nc_io_minus1"
	string ".handle_low:"
	string "    lda __c_io_write__v00"
	string "    cmp #NC_IO_HANDLE_COUNT"
	string "    bcc .in_range"
	string "    jmp __nc_io_minus1"
	string ".in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    cmp #NC_IO_OUTPUT"
	string "    beq .open"
	string "    jmp __nc_io_minus1"
	string ".open:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    tax"
	string "    jsr $ffc9      ; CHKOUT"
	string "    bcc .selected"
	string "    jmp .error_clear"
	string ".selected:"
	string "    lda __c_io_write__v01"
	string "    jsr $ffd2      ; CHROUT"
	string "    jsr $ffb7      ; READST"
	string "    sta NC_TMP"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda NC_TMP"
	string "    beq .ok"
	string "    jmp __nc_io_minus1"
	string ".ok:"
	string "    jmp __nc_io_zero"
	string ".error_clear:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    jmp __nc_io_minus1"
	byte 0

runtimeCloseText:
	string "__c_io_close:"
	string "    cld"
	string "    lda __c_io_close__v00+1"
	string "    beq .handle_low"
	string "    jmp __nc_io_minus1"
	string ".handle_low:"
	string "    lda __c_io_close__v00"
	string "    cmp #NC_IO_HANDLE_COUNT"
	string "    bcc .in_range"
	string "    jmp __nc_io_minus1"
	string ".in_range:"
	string "    sta __nc_io_handle"
	string "    tax"
	string "    lda __nc_io_mode,x"
	string "    bne .open"
	string "    jmp __nc_io_minus1"
	string ".open:"
	string "    jsr $ffcc      ; CLRCHN"
	string "    lda __nc_io_handle"
	string "    clc"
	string "    adc #NC_IO_LFN_BASE"
	string "    jsr $ffc3      ; CLOSE"
	string "    ldx __nc_io_handle"
	string "    lda #$00"
	string "    sta __nc_io_mode,x"
	string "    sta __nc_io_eof,x"
	string "    jmp __nc_io_zero"
	byte 0
