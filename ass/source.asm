;;; source.asm
;;;
;;; Direct C64 KERNAL sequential source input. Only one 256-byte caller-owned
;;; line buffer is resident; included files remain open on a tiny fixed channel
;;; stack so EOF can resume the parent at its existing position.
;;;
;;; sourceDirectory is optional. When its length is nonzero, local include names
;;; are prefixed with that one directory into sourcePathBuffer. A leading `../`
;;; drops the prefix instead. This is deliberately only the path behavior nanoc's
;;; real source tree needs; it is not a general path normalizer.

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
;;; Include-name construction borrows ZP_PTR1 internally, so this routine owns
;;; preserving the parser cursor rather than requiring its caller to know that.
includeSource:
	lda ZP_PTR1
	pha
	lda ZP_PTR1+1
	pha
	jsr includeSourceBody
	tax
	pla
	sta ZP_PTR1+1
	pla
	sta ZP_PTR1
	txa
	rts

includeSourceBody:
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
	jsr prepareIncludeName
	bcc .nameBad
	jsr openSourceAtDepth
	cmp #ASSEMBLE_OK
	beq .ok
	dec sourceDepth
	pha
	jsr selectSourceAtDepth		; restore parent input channel
	pla
	rts
.ok:
	ldx sourceDepth
	lda #$00
	sta sourceEofPending,x		; leave the parent's pending EOF untouched
	lda #ASSEMBLE_OK
	rts
.nameBad:
	dec sourceDepth
.bad:
	lda #ASSEMBLE_BAD_STATEMENT
	rts
.depth:
	lda #ASSEMBLE_INCLUDE_DEPTH
	rts

;;; prepareIncludeName
;;; With no configured sourceDirectory, keep the old zero-copy filename view.
;;; Otherwise construct a KERNAL filename in sourcePathBuffer:
;;;
;;;     "parser.asm"        -> sourceDirectory + "PARSER.ASM"
;;;     "../dis/table.asm"  -> "DIS/TABLE.ASM"
;;;
;;; Source files are ASCII text while the C64 filename bytes expected by VICE's
;;; filesystem device use the upper-case PETSCII/ASCII range, so a-z is folded to
;;; A-Z while copying. Carry set means openName/openNameLength are ready.
prepareIncludeName:
	lda sourceDirectoryLength
	bne .build

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
	sec
	rts

.build:
	lda sourcePathBuffer
	ora sourcePathBuffer+1
	bne .bufferReady
	jmp .bad
.bufferReady:
	lda sourcePathBuffer
	sta ZP_PTR1
	sta openName
	lda sourcePathBuffer+1
	sta ZP_PTR1+1
	sta openName+1
	lda #$00
	sta sourcePathLength

	;; Point ZP_PTR0 at the first byte inside the quotes and detect the only
	;; parent form needed by the production tree: ../dis/...
	clc
	lda statementArgument
	adc #$01
	sta ZP_PTR0
	lda statementArgument+1
	adc #$00
	sta ZP_PTR0+1
	lda #$00
	sta sourceInputOffset
	lda statementArgumentLength
	sec
	sbc #$02
	sta sourceInputLength
	cmp #$03
	bcc .local
	ldy #$00
	lda (ZP_PTR0),y
	cmp #'.'
	bne .local
	iny
	lda (ZP_PTR0),y
	cmp #'.'
	bne .local
	iny
	lda (ZP_PTR0),y
	cmp #'/'
	bne .local
	lda #$03
	sta sourceInputOffset
	jmp .filename

.local:
	;; Every local production include lives in the configured one directory.
	lda sourceDirectory
	sta ZP_PTR0
	lda sourceDirectory+1
	sta ZP_PTR0+1
	lda #$00
	sta sourceInputOffset
.copyDirectory:
	lda sourceInputOffset
	cmp sourceDirectoryLength
	beq .directoryDone
	ldy sourceInputOffset
	lda (ZP_PTR0),y
	jsr appendPathByte
	bcc .bad
	inc sourceInputOffset
	jmp .copyDirectory
.directoryDone:
	lda #$00
	sta sourceInputOffset

	clc
	lda statementArgument
	adc #$01
	sta ZP_PTR0
	lda statementArgument+1
	adc #$00
	sta ZP_PTR0+1

.filename:
	lda sourceInputOffset
	cmp sourceInputLength
	beq .done
	ldy sourceInputOffset
	lda (ZP_PTR0),y
	cmp #'a'
	bcc .copy
	cmp #'z'+1
	bcs .copy
	and #$df			; ASCII lower-case source -> C64 filename byte
.copy:
	jsr appendPathByte
	bcc .bad
	inc sourceInputOffset
	jmp .filename
.done:
	lda sourcePathLength
	beq .bad
	sta openNameLength
	sec
	rts
.bad:
	clc
	rts

;;; appendPathByte
;;; Append A to sourcePathBuffer. The one-byte KERNAL filename length makes 255
;;; bytes the natural hard limit. Carry clear means there is no room.
appendPathByte:
	ldx sourcePathLength
	cpx #$ff
	beq .full
	pha
	txa
	tay
	pla
	sta (ZP_PTR1),y
	inc sourcePathLength
	sec
	rts
.full:
	clc
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
	ldx sourceDepth
	lda sourceEofPending,x
	beq .newLine
	lda #$00
	sta sourceEofPending,x
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
	ldx sourceDepth
	lda #$01
	sta sourceEofPending,x
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
	ldx sourceDepth
	lda sourceEofPending,x
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
;;; EOI belongs to the open source that observed it. A parent can already be at
;;; EOF while its final include is being read, so keep one byte per source depth.
sourceEofPending:	byte 0,0,0,0,0
sourceByte:		byte 0
sourceStatus:		byte 0
openName:		word 0
openNameLength:		byte 0

;;; Optional simple include-path configuration. A zero length keeps the original
;;; direct filename behavior used by small tests.
sourceDirectory:	word 0
sourceDirectoryLength:	byte 0
sourcePathBuffer:	word 0
sourcePathLength:	byte 0
sourceInputOffset:	byte 0
sourceInputLength:	byte 0
