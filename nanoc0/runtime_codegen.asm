;;; runtime_codegen.asm
;;;
;;; Final generated-program support for Nano C Phase 1.
;;;
;;; The compiler emits the small dynamic facts itself, then names ordinary target
;;; assembly files for fixed runtime routines. Keeping those already-readable
;;; routines as assembler source avoids carrying a second text copy of them inside
;;; nanoc0's resident image. There is still no intermediate representation: the
;;; output is direct `ass` source and the include files contain the exact 6502 code
;;; that will run.
;;;
;;; Runtime-private target BSS remains allocated here so the final NC_BSS size is
;;; known before deferred string data is emitted.

RUNTIME_HANDLE_CAPACITY = 6

emit_runtime_support:
	jsr prepare_runtime_storage
	bcc .failed
	jsr emit_runtime_init
	bcc .failed

	lda multiplyUsed
	beq .runtimeCheck
	ldx #<runtimeMulPath
	ldy #>runtimeMulPath
	jsr emit_runtime_include
	bcc .failed

.runtimeCheck:
	jsr runtime_any_used
	bcc .done
	ldx #<runtimeCommonPath
	ldy #>runtimeCommonPath
	jsr emit_runtime_include
	bcc .failed

	lda runtimeUsed
	beq .read
	ldx #<runtimeOpenPath
	ldy #>runtimeOpenPath
	jsr emit_runtime_include
	bcc .failed
.read:
	lda runtimeUsed+1
	beq .create
	ldx #<runtimeReadPath
	ldy #>runtimeReadPath
	jsr emit_runtime_include
	bcc .failed
.create:
	lda runtimeUsed+2
	beq .write
	ldx #<runtimeCreatePath
	ldy #>runtimeCreatePath
	jsr emit_runtime_include
	bcc .failed
.write:
	lda runtimeUsed+3
	beq .close
	ldx #<runtimeWritePath
	ldy #>runtimeWritePath
	jsr emit_runtime_include
	bcc .failed
.close:
	lda runtimeUsed+4
	beq .done
	ldx #<runtimeClosePath
	ldy #>runtimeClosePath
	jsr emit_runtime_include
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

runtime_any_used:
	ldx #$00
.loop:
	lda runtimeUsed,x
	bne .yes
	inx
	cpx #RUNTIME_SYMBOL_COUNT
	bne .loop
	clc
	rts
.yes:
	sec
	rts

;;; Runtime-private BSS is allocated after C function storage. The final caller
;;; then emits __nc_bss_end from the updated bssOffset.
prepare_runtime_storage:
	jsr runtime_any_used
	bcs .needed
	sec
	rts
.needed:
	lda #RUNTIME_HANDLE_CAPACITY
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	ldx #<runtimeModeName
	ldy #>runtimeModeName
	jsr emit_runtime_definition
	bcc .failed

	lda #RUNTIME_HANDLE_CAPACITY
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	ldx #<runtimeEofName
	ldy #>runtimeEofName
	jsr emit_runtime_definition
	bcc .failed

	lda #$01
	sta allocSize
	lda #$00
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	ldx #<runtimeHandleName
	ldy #>runtimeHandleName
	jsr emit_runtime_definition
	bcc .failed

	lda runtimeUsed+2
	beq .done
	lda #$00
	sta allocSize
	lda #$01
	sta allocSize+1
	jsr allocate_bss
	bcc .failed
	ldx #<runtimeNameBufferName
	ldy #>runtimeNameBufferName
	jsr emit_runtime_definition
	bcc .failed
.done:
	sec
	rts
.failed:
	clc
	rts

;;; X/Y=address of a fixed generated symbol name. allocOffset is the allocation
;;; just committed.
emit_runtime_definition:
	jsr emit_string
	bcc .failed
	ldx #<runtimeBssAssign
	ldy #>runtimeBssAssign
	jsr emit_string
	bcc .failed
	lda allocOffset
	sta emitWord
	lda allocOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; zeroRequiredEnd is the exact number of source-global bytes with C zero-init
;;; semantics. Function storage and runtime state are not swept by this loop.
emit_runtime_init:
	ldx #<runtimeInitPrefix
	ldy #>runtimeInitPrefix
	jsr emit_runtime_lines
	bcc .failed
	ldx #<runtimeLdaImmediate
	ldy #>runtimeLdaImmediate
	jsr emit_string
	bcc .failed
	lda zeroRequiredEnd
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<runtimeStaTmp
	ldy #>runtimeStaTmp
	jsr emit_string
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<runtimeLdaImmediate
	ldy #>runtimeLdaImmediate
	jsr emit_string
	bcc .failed
	lda zeroRequiredEnd+1
	jsr emit_hex_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<runtimeStaTmpHigh
	ldy #>runtimeStaTmpHigh
	jsr emit_string
	bcc .failed
	jsr emit_newline
	bcc .failed
	ldx #<runtimeInitClearText
	ldy #>runtimeInitClearText
	jsr emit_runtime_lines
	bcc .failed
	jsr runtime_any_used
	bcc .return
	ldx #<runtimeInitIoText
	ldy #>runtimeInitIoText
	jsr emit_runtime_lines
	bcc .failed
.return:
	ldx #<runtimeInitReturnText
	ldy #>runtimeInitReturnText
	jmp emit_runtime_lines
.failed:
	clc
	rts

;;; X/Y=address of a fixed NUL-terminated path. Emit one ordinary ass include
;;; statement. Production ass roots local includes at ASS/, so ../ deliberately
;;; drops that prefix and reaches the repository-level nanoc0 target directory.
emit_runtime_include:
	stx runtimeIncludePath
	sty runtimeIncludePath+1
	ldx #<runtimeIncludePrefix
	ldy #>runtimeIncludePrefix
	jsr emit_string
	bcc .failed
	ldx runtimeIncludePath
	ldy runtimeIncludePath+1
	jsr emit_string
	bcc .failed
	lda #'"'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; Consecutive NUL-terminated `string` lines with one extra NUL form a tiny
;;; readable text slab. This is used for the short dynamic startup wrapper and by
;;; nanoc0.asm for the generated program header/entry only.
emit_runtime_lines:
	stx EMIT_PTR
	sty EMIT_PTR+1
.loop:
	ldy #$00
	lda (EMIT_PTR),y
	beq .lineEnd
	jsr emit_output_byte
	bcc .failed
	inc EMIT_PTR
	bne .loop
	inc EMIT_PTR+1
	jmp .loop
.lineEnd:
	lda #$0a
	jsr emit_output_byte
	bcc .failed
	inc EMIT_PTR
	bne .peek
	inc EMIT_PTR+1
.peek:
	ldy #$00
	lda (EMIT_PTR),y
	bne .loop
	sec
	rts
.failed:
	clc
	rts

runtimeModeName:	byte '_','_','n','c','_','i','o','_','m','o','d','e',0
runtimeEofName:		byte '_','_','n','c','_','i','o','_','e','o','f',0
runtimeHandleName:	byte '_','_','n','c','_','i','o','_','h','a','n','d','l','e',0
runtimeNameBufferName:	byte '_','_','n','c','_','i','o','_','n','a','m','e',0
runtimeBssAssign:	byte ' ','=',' ','N','C','_','B','S','S','+','$',0
runtimeLdaImmediate:	byte $09,'l','d','a',' ','#','$',0
runtimeStaTmp:		byte $09,'s','t','a',' ','N','C','_','T','M','P',0
runtimeStaTmpHigh:	byte $09,'s','t','a',' ','N','C','_','T','M','P','+','1',0
runtimeIncludePrefix:	byte $09,'i','n','c','l','u','d','e',' ','"',0

runtimeMulPath:		byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','m','u','l','1','6','.','a','s','m',0
runtimeCommonPath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','c','o','m','m','o','n','.','a','s','m',0
runtimeOpenPath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','o','p','e','n','.','a','s','m',0
runtimeReadPath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','r','e','a','d','.','a','s','m',0
runtimeCreatePath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','c','r','e','a','t','e','.','a','s','m',0
runtimeWritePath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','w','r','i','t','e','.','a','s','m',0
runtimeClosePath:	byte '.','.','/','n','a','n','o','c','0','/','t','a','r','g','e','t','/','i','o','-','c','l','o','s','e','.','a','s','m',0

runtimeInitPrefix:
	string "__nc_init:"
	string "	cld"
	string "	lda #<NC_BSS"
	string "	sta NC_PTR"
	string "	lda #>NC_BSS"
	string "	sta NC_PTR+1"
	byte 0

runtimeInitClearText:
	string "	ldy #$00"
	string ".clear_globals:"
	string "	lda NC_TMP"
	string "	ora NC_TMP+1"
	string "	beq .globals_done"
	string "	lda #$00"
	string "	sta (NC_PTR),y"
	string "	inc NC_PTR"
	string "	bne .pointer_done"
	string "	inc NC_PTR+1"
	string ".pointer_done:"
	string "	lda NC_TMP"
	string "	bne .decrement_low"
	string "	dec NC_TMP+1"
	string ".decrement_low:"
	string "	dec NC_TMP"
	string "	jmp .clear_globals"
	string ".globals_done:"
	byte 0

runtimeInitIoText:
	string "	lda #$00"
	string "	ldx #$05        ; six runtime handles"
	string ".clear_io:"
	string "	sta __nc_io_mode,x"
	string "	sta __nc_io_eof,x"
	string "	dex"
	string "	bpl .clear_io"
	byte 0

runtimeInitReturnText:
	string "	cld"
	string "	rts"
	byte 0

runtimeIncludePath:	word 0
