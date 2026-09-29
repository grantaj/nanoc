;;; nanoc1 Phase 1 target runtime.
;;;
;;; The semantic baseline intentionally reuses the proven arithmetic/comparison
;;; and byte-stream routines from nanoc0.  Its own fixed runtime workspace sits
;;; above the user BSS ceiling used by nanoc1 ($ce00), leaving code generation
;;; and language semantics independent of I/O bookkeeping.

__nc_io_mode   = $ce00
__nc_io_eof    = $ce06
__nc_io_handle = $ce0c
__nc_io_name   = $ce10

__nc_init:
	cld
	lda #<NC_BSS
	sta NC_PTR
	lda #>NC_BSS
	sta NC_PTR+1
	lda #<__nc_bss_bytes
	sta NC_TMP
	lda #>__nc_bss_bytes
	sta NC_TMP+1
	ldy #$00
.clear_bss:
	lda NC_TMP
	ora NC_TMP+1
	beq .clear_runtime
	lda #$00
	sta (NC_PTR),y
	inc NC_PTR
	bne .pointer_ok
	inc NC_PTR+1
.pointer_ok:
	lda NC_TMP
	bne .dec_low
	dec NC_TMP+1
.dec_low:
	dec NC_TMP
	jmp .clear_bss
.clear_runtime:
	lda #$00
	ldx #$05
.clear_io:
	sta __nc_io_mode,x
	sta __nc_io_eof,x
	dex
	bpl .clear_io
	cld
	rts

	include "../nanoc0/target/compare16.asm"
	include "../nanoc0/target/mul16.asm"
	include "../nanoc0/target/io-common.asm"
	include "../nanoc0/target/io-open.asm"
	include "../nanoc0/target/io-read.asm"
	include "../nanoc0/target/io-create.asm"
	include "../nanoc0/target/io-write.asm"
	include "../nanoc0/target/io-close.asm"