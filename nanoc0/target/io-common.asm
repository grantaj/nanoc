;;; Nano C target runtime: common C64 I/O support.

NC_IO_INPUT        = $01
NC_IO_OUTPUT       = $02
NC_IO_PREFETCH     = $03
NC_IO_PREFETCH_EOF = $04
NC_IO_HANDLE_COUNT = $06
NC_IO_LFN_BASE     = $04
NC_IO_READ_DEVICE  = $08
NC_IO_WRITE_DEVICE = $09

__nc_io_zero:
	lda #$00
	ldx #$00
	cld
	rts

__nc_io_minus1:
	lda #$ff
	ldx #$ff
	cld
	rts

__nc_io_minus2:
	lda #$fe
	ldx #$ff
	cld
	rts
