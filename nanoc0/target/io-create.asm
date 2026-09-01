;;; Nano C target runtime: io_create(name, length).

__c_io_create:
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
	lda __c_io_create__v01+1
	beq .length_low
	jmp __nc_io_minus1
.length_low:
	lda __c_io_create__v01
	cmp #$f9       ; room for @0: and ,S,W
	bcc .length_ok
	jmp __nc_io_minus1
.length_ok:
	lda #'@'
	sta __nc_io_name
	lda #'0'
	sta __nc_io_name+1
	lda #':'
	sta __nc_io_name+2
	lda __c_io_create__v00
	sta NC_PTR
	lda __c_io_create__v00+1
	sta NC_PTR+1
	ldy #$00
.copy:
	cpy __c_io_create__v01
	beq .suffix
	lda (NC_PTR),y
	sta __nc_io_name+3,y
	iny
	jmp .copy
.suffix:
	tya
	clc
	adc #$03
	tax
	lda #','
	sta __nc_io_name,x
	inx
	lda #'S'
	sta __nc_io_name,x
	inx
	lda #','
	sta __nc_io_name,x
	inx
	lda #'W'
	sta __nc_io_name,x
	jsr $ffcc      ; CLRCHN
	lda __c_io_create__v01
	clc
	adc #$07
	ldx #<__nc_io_name
	ldy #>__nc_io_name
	jsr $ffbd      ; SETNAM
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	tay
	ldx #NC_IO_WRITE_DEVICE
	jsr $ffba      ; SETLFS
	jsr $ffc0      ; OPEN
	bcc .ok
	lda __nc_io_handle
	clc
	adc #NC_IO_LFN_BASE
	jsr $ffc3      ; CLOSE
	jmp __nc_io_minus1
.ok:
	ldx __nc_io_handle
	lda #NC_IO_OUTPUT
	sta __nc_io_mode,x
	lda #$00
	sta __nc_io_eof,x
	txa
	ldx #$00
	cld
	rts
