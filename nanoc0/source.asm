;;; source.asm
;;;
;;; Streaming Nano C source input.
;;;
;;; The source reader owns one C64 KERNAL sequential file and one byte of
;;; pushback.  It normalises CR and CRLF to LF and advances sourceLine when a
;;; physical newline is first read.  Replaying a pushed-back byte never advances
;;; the line a second time.
;;;
;;; The compiler alternates reading C source and writing generated assembler on
;;; the same serial device. CHKIN/CHKOUT therefore also alternate the physical
;;; IEC TALK/LISTEN state. Each real source read explicitly reselects this input
;;; logical file before CHRIN rather than relying on the logical file merely
;;; remaining open.
;;;
;;; read_source_byte contract:
;;;   carry set   A = next source byte
;;;   carry clear A = SOURCE_STATE_EOF or SOURCE_STATE_IO_ERROR

	include "../dis/kernal.inc"

SOURCE_LFN_DEFAULT       = 2
SOURCE_STATUS_EOI        = $40
SOURCE_STATE_OK          = 0
SOURCE_STATE_EOF         = 1
SOURCE_STATE_IO_ERROR    = 2
SOURCE_LF                = $0a
SOURCE_CR                = $0d

;;; open_source
;;; sourceName/sourceNameLength/sourceDevice identify the source file.
;;; Carry set means the KERNAL input channel is ready.
open_source:
	jsr close_source
	lda #SOURCE_STATE_OK
	sta sourceState
	lda #$00
	sta sourcePushbackValid
	sta sourceEofPending
	sta sourceSkipLf
	sta sourceLine+1
	lda #$01
	sta sourceLine

	jsr CLRCHN
	lda sourceNameLength
	ldx sourceName
	ldy sourceName+1
	jsr SETNAM
	lda sourceLfn
	ldx sourceDevice
	ldy sourceLfn
	jsr SETLFS
	jsr OPEN
	bcs .error
	lda #$01
	sta sourceOpen
	ldx sourceLfn
	jsr CHKIN
	bcc .ok
.error:
	;; CLOSE is harmless after a failed OPEN and also cleans up a CHKIN failure.
	jsr CLRCHN
	lda sourceLfn
	jsr CLOSE
	lda #$00
	sta sourceOpen
	lda #SOURCE_STATE_IO_ERROR
	sta sourceState
	clc
	rts
.ok:
	sec
	rts

;;; close_source
;;; Close only the logical file owned by this source reader.
close_source:
	lda sourceOpen
	beq .done
	jsr CLRCHN
	lda sourceLfn
	jsr CLOSE
	lda #$00
	sta sourceOpen
.done:
	rts

;;; read_source_byte
;;; Carry set: A is one normalised source byte.
;;; Carry clear: A is SOURCE_STATE_EOF or SOURCE_STATE_IO_ERROR.
read_source_byte:
	lda sourcePushbackValid
	beq .notPushed
	lda #$00
	sta sourcePushbackValid
	lda sourcePushbackByte
	sec
	rts

.notPushed:
	lda sourceState
	cmp #SOURCE_STATE_OK
	beq .raw
	clc
	rts

.raw:
	lda sourceEofPending
	beq .read
	jsr close_source
	lda #SOURCE_STATE_EOF
	sta sourceState
	clc
	rts

.read:
	;;; Generated output may have selected another serial channel since the last
	;;; byte. Re-select this logical input before asking the device to talk.
	ldx sourceLfn
	jsr CHKIN
	bcs .ioError
	jsr CHRIN
	sta sourceByte
	jsr READST
	sta sourceKernalStatus

	;; EOI accompanies the final valid byte.  Any other status is an error.
	and #$bf
	beq .statusOk
.ioError:
	jsr close_source
	lda #SOURCE_STATE_IO_ERROR
	sta sourceState
	clc
	rts

.statusOk:
	lda sourceKernalStatus
	and #SOURCE_STATUS_EOI
	beq .haveByte
	lda #$01
	sta sourceEofPending

.haveByte:
	;; A raw LF immediately following CR is the second half of CRLF.  Discard it;
	;; the CR was already returned as LF and counted as the physical newline.
	lda sourceSkipLf
	beq .normalise
	lda #$00
	sta sourceSkipLf
	lda sourceByte
	cmp #SOURCE_LF
	beq .raw

.normalise:
	lda sourceByte
	cmp #SOURCE_CR
	bne .checkLf
	lda #$01
	sta sourceSkipLf
	lda #SOURCE_LF
	jsr increment_source_line
	sec
	rts
.checkLf:
	cmp #SOURCE_LF
	bne .returnByte
	jsr increment_source_line
	lda #SOURCE_LF
.returnByte:
	sec
	rts

;;; push_source_byte
;;; Push back only the byte just returned by read_source_byte.  If it was LF,
;;; sourceLine has already advanced; replaying it does not advance again.
push_source_byte:
	sta sourcePushbackByte
	lda #$01
	sta sourcePushbackValid
	rts

increment_source_line:
	inc sourceLine
	bne .done
	inc sourceLine+1
.done:
	rts

;;; Source configuration supplied by the caller.
sourceName:		word 0
sourceNameLength:	byte 0
sourceDevice:		byte 8
sourceLfn:		byte SOURCE_LFN_DEFAULT

;;; Persistent source state.
sourceOpen:		byte 0
sourceState:		byte SOURCE_STATE_EOF
sourcePushbackValid:	byte 0
sourcePushbackByte:	byte 0
sourceEofPending:	byte 0
sourceSkipLf:		byte 0
sourceLine:		word 1

;;; KERNAL read scratch.
sourceByte:		byte 0
sourceKernalStatus:	byte 0
