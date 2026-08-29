;;; source.asm
;;;
;;; Direct C64 KERNAL sequential source input. Only one 256-byte caller-owned
;;; line buffer is resident; included files remain open on a tiny fixed channel
;;; stack so EOF can resume the parent at its existing position.

	include "../dis/kernal.inc"

SOURCE_LFN_BASE   = 2
SOURCE_MAX_DEPTH  = 4			; root plus four nested includes
SOURCE_EOL_CR     = $0d
SOURCE_EOL_LF     = $0a
SOURCE_STATUS_EOI = $40

;;; openRootSource
;;; sourceName/sourceNameLength/sourceDevice identify the root file.
openRootSource:
	lda #$00
	sta sourceDepth
	sta sourceEofPending
	lda sourceName
	sta openName
	lda sourceName+1
	sta openName+1
	lda sourceNameLength
	sta openNameLength
	jsr openSourceAtDepth
	rts

;;; includeSource
;;; statementArgument must be exactly one quoted filename. Open it as the next
;;; input channel; the parent remains open and positioned after the include line.
includeSource:
	lda statementArgumentLength
	cmp #$03
	bcc .bad
	lda statementArgument
	sta ZP_PTR0
	lda statementArgument+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'"'
	bne .bad
	ldy statementArgumentLength
	dey
	lda (ZP_PTR0),y
	cmp #'"'
	bne .bad

	lda sourceDepth
	cmp #SOURCE_MAX_DEPTH
	bcs .depth
	inc sourceDepth
	clc
	lda statementArgument
	adc #$01
	sta openName
	lda statementArgument+1
	adc #$00
	sta openName+1
	lda statementArgumentLength
	sec
	sbc #$02
	sta openNameLength
	jsr openSourceAtDepth
	cmp #ASSEMBLE_OK
	beq .ok
	dec sourceDepth
	pha
	jsr selectSourceAtDepth		; restore parent input channel
	pla
	rts
.ok:
	lda #$00
	sta sourceEofPending
	lda #ASSEMBLE_OK
	rts
.bad:
	lda #ASSEMBLE_BAD_STATEMENT
	rts
.depth:
	lda #ASSEMBLE_INCLUDE_DEPTH
	rts

;;; openSourceAtDepth
;;; LFN and device secondary address are both SOURCE_LFN_BASE+sourceDepth.  A
;;; parent include must retain its own device channel while its child is read.
;;; Any partially opened logical file is closed before an error is returned.
openSourceAtDepth:
	jsr CLRCHN
	lda openNameLength
	ldx openName
	ldy openName+1
	jsr SETNAM
	lda sourceDepth
	clc
	adc #SOURCE_LFN_BASE
	sta sourceCurrentLfn
	lda sourceCurrentLfn
	ldx sourceDevice
	ldy sourceCurrentLfn
	jsr SETLFS
	jsr OPEN
	bcs .error
	ldx sourceCurrentLfn
	jsr CHKIN
	bcc .ok
.error:
	lda sourceCurrentLfn
	jsr CLOSE
	lda #ASSEMBLE_IO_ERROR
	rts
.ok:
	lda #ASSEMBLE_OK
	rts

;;; selectSourceAtDepth
;;; Select the already-open channel for sourceDepth.
selectSourceAtDepth:
	lda sourceDepth
	clc
	adc #SOURCE_LFN_BASE
	sta sourceCurrentLfn
	ldx sourceCurrentLfn
	jsr CHKIN
	rts

;;; readSourceLine
;;; Read one logical source line into sourceLineBuffer and append NUL.
;;;
;;; Carry set: one line is ready, sourceLineLength is 0..255.
;;; Carry clear/A=ASSEMBLE_OK: root EOF.
;;; Carry clear/A!=ASSEMBLE_OK: I/O or line-length error.
;;;
;;; CR and LF both end a line. CRLF therefore yields one harmless blank line.
readSourceLine:
.start:
	lda sourceEofPending
	beq .newLine
	lda #$00
	sta sourceEofPending
	jsr finishSourceFile
	bcs .start			; child EOF: continue parent
	rts				; root EOF or parent-channel error

.newLine:
	lda #$00
	sta sourceLineLength
.read:
	jsr CHRIN
	sta sourceByte
	jsr READST
	sta sourceStatus

	;; EOI is normal. Any other serial/file status is an input error.
	lda sourceStatus
	and #$bf
	beq .statusOk
	jsr closeSourceTree
	lda #ASSEMBLE_IO_ERROR
	clc
	rts
.statusOk:
	lda sourceStatus
	and #SOURCE_STATUS_EOI
	beq .notLast
	lda #$01
	sta sourceEofPending
.notLast:
	lda sourceByte
	cmp #SOURCE_EOL_CR
	beq .lineDone
	cmp #SOURCE_EOL_LF
	beq .lineDone

	lda sourceLineLength
	cmp #$ff
	beq .tooLong
	lda sourceLineBuffer
	sta ZP_PTR0
	lda sourceLineBuffer+1
	sta ZP_PTR0+1
	ldy sourceLineLength
	lda sourceByte
	sta (ZP_PTR0),y
	inc sourceLineLength
	lda sourceEofPending
	beq .read

.lineDone:
	jsr terminateSourceLine
	sec
	rts
.tooLong:
	jsr closeSourceTree
	lda #ASSEMBLE_LINE_TOO_LONG
	clc
	rts

terminateSourceLine:
	lda sourceLineBuffer
	sta ZP_PTR0
	lda sourceLineBuffer+1
	sta ZP_PTR0+1
	ldy sourceLineLength
	lda #$00
	sta (ZP_PTR0),y
	rts

;;; prepareSourceLine
;;; Present the current NUL-terminated line using the parser's existing
;;; [ZP_PTR1,sourceEnd) contract.
prepareSourceLine:
	lda sourceLineBuffer
	sta ZP_PTR1
	lda sourceLineBuffer+1
	sta ZP_PTR1+1
	clc
	lda sourceLineBuffer
	adc sourceLineLength
	adc #$01
	sta sourceEnd
	lda sourceLineBuffer+1
	adc #$00
	sta sourceEnd+1
	rts

;;; finishSourceFile
;;; Close current source. Carry set means a child was closed and the parent was
;;; selected. Carry clear returns A=ASSEMBLE_OK for root EOF, or IO error.
finishSourceFile:
	jsr CLRCHN
	lda sourceDepth
	clc
	adc #SOURCE_LFN_BASE
	jsr CLOSE
	lda sourceDepth
	beq .root
	dec sourceDepth
	jsr selectSourceAtDepth
	bcc .parent
	jsr closeSourceTree
	lda #ASSEMBLE_IO_ERROR
	clc
	rts
.parent:
	lda #ASSEMBLE_OK
	sec
	rts
.root:
	lda #ASSEMBLE_OK
	clc
	rts

;;; closeSourceTree
;;; Error cleanup for only the logical files owned by this reader.
closeSourceTree:
	jsr CLRCHN
.loop:
	lda sourceDepth
	clc
	adc #SOURCE_LFN_BASE
	jsr CLOSE
	lda sourceDepth
	beq .done
	dec sourceDepth
	jmp .loop
.done:
	rts

sourceName:		word 0
sourceNameLength:	byte 0
sourceDevice:		byte 8
sourceLineBuffer:	word 0
sourceLineLength:	byte 0
sourceDepth:		byte 0
sourceCurrentLfn:	byte 0
sourceEofPending:	byte 0
sourceByte:		byte 0
sourceStatus:		byte 0
openName:		word 0
openNameLength:		byte 0
