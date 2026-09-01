;;; Nano C target runtime: io_write(handle, value).

__c_io_write:
	cld
	lda __c_io_write__v00+1
	beq .handle_low
	jmp __nc_io_minus1
.handle_low:
	lda __c_io_write__v00
	cmp #NC_IO_HANDLE_COUNT
	bcc .in_range
	jmp __nc_io_minus1
.in_range:
	sta __nc_io_handle
	tax
	lda __nc_io_mode,x
	cmp #NC_IO_OUTPUT
	beq .open
	jmp __nc_io_minus1
.open:
	jsr $ffcc      ; CLRCHN
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	tax
	jsr $ffc9      ; CHKOUT
	bcc .selected
	jmp .error_clear
.selected:
	lda __c_io_write__v01
	jsr $ffd2      ; CHROUT
	jsr $ffb7      ; READST
	sta NC_TMP
	jsr $ffcc      ; CLRCHN
	lda NC_TMP
	beq .ok
	jmp __nc_io_minus1
.ok:
	jmp __nc_io_zero
.error_clear:
	jsr $ffcc      ; CLRCHN
	jmp __nc_io_minus1
