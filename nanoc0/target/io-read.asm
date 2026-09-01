;;; Nano C target runtime: io_read(handle).

__c_io_read:
	cld
	lda __c_io_read__v00+1
	beq .handle_low
	jmp __nc_io_minus2
.handle_low:
	lda __c_io_read__v00
	cmp #NC_IO_HANDLE_COUNT
	bcc .in_range
	jmp __nc_io_minus2
.in_range:
	sta __nc_io_handle
	tax
	lda __nc_io_mode,x
	cmp #NC_IO_INPUT
	beq .open
	cmp #NC_IO_PREFETCH
	beq .prefetch
	cmp #NC_IO_PREFETCH_EOF
	beq .prefetch_eof
	jmp __nc_io_minus2
.prefetch:
	lda __nc_io_eof,x
	sta NC_TMP
	lda #$00
	sta __nc_io_eof,x
	lda #NC_IO_INPUT
	sta __nc_io_mode,x
	lda NC_TMP
	ldx #$00
	cld
	rts
.prefetch_eof:
	lda __nc_io_eof,x
	sta NC_TMP
	lda #$01
	sta __nc_io_eof,x
	lda #NC_IO_INPUT
	sta __nc_io_mode,x
	lda NC_TMP
	ldx #$00
	cld
	rts
.open:
	lda __nc_io_eof,x
	beq .byte
	jmp __nc_io_minus1
.byte:
	jsr $ffcc      ; CLRCHN
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	tax
	jsr $ffc6      ; CHKIN
	bcc .selected
	jmp .error_clear
.selected:
	jsr $ffcf      ; CHRIN
	sta NC_TMP
	jsr $ffb7      ; READST
	sta NC_TMP+1
	jsr $ffcc      ; CLRCHN
	lda NC_TMP+1
	and #$bf
	beq .status_ok
	jmp __nc_io_minus2
.status_ok:
	lda NC_TMP+1
	and #$40
	beq .return
	ldx __nc_io_handle
	lda #$01
	sta __nc_io_eof,x
.return:
	lda NC_TMP
	ldx #$00
	cld
	rts
.error_clear:
	jsr $ffcc      ; CLRCHN
	jmp __nc_io_minus2
