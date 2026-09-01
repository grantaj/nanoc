;;; Nano C target runtime: io_close(handle).

__c_io_close:
	cld
	lda __c_io_close__v00+1
	beq .handle_low
	jmp __nc_io_minus1
.handle_low:
	lda __c_io_close__v00
	cmp #NC_IO_HANDLE_COUNT
	bcc .in_range
	jmp __nc_io_minus1
.in_range:
	sta __nc_io_handle
	tax
	lda __nc_io_mode,x
	bne .open
	jmp __nc_io_minus1
.open:
	jsr $ffcc      ; CLRCHN
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	jsr $ffc3      ; CLOSE
	ldx __nc_io_handle
	lda #$00
	sta __nc_io_mode,x
	sta __nc_io_eof,x
	jmp __nc_io_zero
