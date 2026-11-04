;;; nanoc2 native I/O boundary. Linked only when a typed built-in is called.
;;; Reuse the proven nanoc0 C64 KERNAL byte-stream routines; do not duplicate
;;; their implementation or compile-time argument rules.
;;;
;;; Their private static slots are exactly the original nanoc1 ABI. Runtime
;;; NC_TMP/NC_PTR borrow $FC-$FF only inside JSR, then the traversal emitter
;;; restores all named caller cursors from original static pointer homes.
;;; The runtime neither owns nor writes the emitter's $CF20+ scratch.
NC_TMP = $fc
NC_PTR = $fe

__nc_io_mode   = $ce00
__nc_io_eof    = $ce06
__nc_io_handle = $ce0c
__nc_io_name   = $ce10

__c_io_open__v00   = $cf10
__c_io_open__v01   = $cf12
__c_io_read__v00   = $cf14
__c_io_create__v00 = $cf16
__c_io_create__v01 = $cf18
__c_io_write__v00  = $cf1a
__c_io_write__v01  = $cf1c
__c_io_close__v00  = $cf1e

__nc_io_init:
	cld
	lda #$00
	ldx #$05
.clear:
	sta __nc_io_mode,x
	sta __nc_io_eof,x
	dex
	bpl .clear
	rts

	include "nanoc0/target/io-common.asm"
	include "nanoc0/target/io-open.asm"
	include "nanoc0/target/io-read.asm"
	include "nanoc0/target/io-create.asm"
	include "nanoc0/target/io-write.asm"
	include "nanoc0/target/io-close.asm"
