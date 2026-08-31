;;; Nano C target runtime: io_open(name, length).

__c_io_open:
	cld
	ldx #$00
.find:
	lda __nc_io_mode,x
	beq .slot
	inx
	cpx #NC_IO_HANDLE_COUNT
	bne .find
	jmp __nc_io_minus1
.slot:
	stx __nc_io_handle
	lda __c_io_open__v01+1
	beq .length_ok
	jmp __nc_io_minus1
.length_ok:
	jsr $ffcc      ; CLRCHN
	lda __c_io_open__v01
	ldx __c_io_open__v00
	ldy __c_io_open__v00+1
	jsr $ffbd      ; SETNAM
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	tay
	ldx #NC_IO_READ_DEVICE
	jsr $ffba      ; SETLFS
	jsr $ffc0      ; OPEN
	bcs .fail
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	tax
	jsr $ffc6      ; CHKIN
	bcs .fail
	jsr $ffcf      ; CHRIN
	sta NC_TMP
	jsr $ffb7      ; READST
	sta NC_TMP+1
	and #$bf
	beq .ok
.fail:
	jsr $ffcc      ; CLRCHN
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	jsr $ffc3      ; CLOSE
	jmp __nc_io_minus1
.ok:
	jsr $ffcc      ; CLRCHN
	ldx __nc_io_handle
	lda NC_TMP
	sta __nc_io_eof,x
	lda NC_TMP+1
	and #$40
	beq .prefetch
	lda #NC_IO_PREFETCH_EOF
	bne .store_mode
.prefetch:
	lda #NC_IO_PREFETCH
.store_mode:
	sta __nc_io_mode,x
	txa
	ldx #$00
	cld
	rts
