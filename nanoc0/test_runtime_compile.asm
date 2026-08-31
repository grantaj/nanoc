	include "../test.inc"

RT_OUTPUT_LFN    = 3
RT_OUTPUT_DEVICE = 9

RT_FAIL_OPEN    = $20
RT_FAIL_OUTPUT  = $21

	* = $4000

main:
	lda #<$3800
	sta bssBase
	lda #>$3800
	sta bssBase+1

	lda #runtimeNameEnd-runtimeName
	sta sourceNameLength
	lda #<runtimeName
	sta sourceName
	lda #>runtimeName
	sta sourceName+1
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	jsr open_source
	bcc .openFailed

	jsr rt_open_output
	bcc .outputFailed
	ldx #<rtHeader
	ldy #>rtHeader
	jsr emit_runtime_lines
	bcc .outputFailed
	jsr parse_translation_unit
	bcc .compileFailed
	jsr rt_close_output
	lda #TEST_PASS
	jmp .finish

.openFailed:
	lda #RT_FAIL_OPEN
	jmp .finish
.outputFailed:
	jsr close_source
	jsr rt_close_output
	lda #RT_FAIL_OUTPUT
	jmp .finish
.compileFailed:
	lda parserError
	cmp #PARSE_SCANNER_ERROR
	beq .scannerDiagnostic
	cmp #PARSE_EXPRESSION_ERROR
	bne .parserDiagnostic
	lda expressionError
	ora #$80
	jmp .closeDiagnostic
.scannerDiagnostic:
	lda scannerError
	ora #$20
	jmp .closeDiagnostic
.parserDiagnostic:
	ora #$40
.closeDiagnostic:
	sta rtDiagnostic
	jsr close_source
	jsr rt_close_output
	lda rtDiagnostic
.finish:
	sta TEST_RESULT
.halt:
	jmp .halt

rt_open_output:
	lda #outputNameEnd-outputName
	ldx #<outputName
	ldy #>outputName
	jsr SETNAM
	lda #RT_OUTPUT_LFN
	ldx #RT_OUTPUT_DEVICE
	ldy #RT_OUTPUT_LFN
	jsr SETLFS
	jsr OPEN
	bcs .failed
	lda #$01
	sta rtOutputOpen
	sta emitOutputEnabled
	sec
	rts
.failed:
	clc
	rts

rt_close_output:
	lda #$00
	sta emitOutputEnabled
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda rtOutputOpen
	beq .done
	lda #RT_OUTPUT_LFN
	jsr CLOSE
	lda #$00
	sta rtOutputOpen
.done:
	rts

;;; ---------------------------------------------------------------------------
;;; Direct declaration emission used by this one generated program
;;; ---------------------------------------------------------------------------

emit_persistent_symbol:
	sta rtStorageKind
	stx rtSavedSymbol
	cmp #EMIT_STORAGE_BSS
	beq .bss
	cmp #EMIT_STORAGE_DATA
	beq .data
	ldx rtSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.bss:
	ldx rtSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	jmp rt_emit_bss_assignment
.data:
	ldx rtSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

emit_current_symbol:
	stx rtSavedSymbol
	jsr emit_current_name
	bcc .failed
	jmp rt_emit_bss_assignment
.failed:
	clc
	rts

emit_static_byte:
	sta rtStaticByte
	lda #rtBytePrefixEnd-rtBytePrefix
	ldx #<rtBytePrefix
	ldy #>rtBytePrefix
	jsr emit_text
	bcc .failed
	lda rtStaticByte
	jsr emit_hex_byte
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

;;; Runtime-private storage must be allocated before the final BSS size is
;;; spelled. The emitted support then sits before deferred string-literal data.
emit_bss_boundaries:
	jsr emit_runtime_support
	bcc .failed
	lda #rtBssEndPrefixEnd-rtBssEndPrefix
	ldx #<rtBssEndPrefix
	ldy #>rtBssEndPrefix
	jsr emit_text
	bcc .failed
	lda bssOffset
	sta emitWord
	lda bssOffset+1
	sta emitWord+1
	jsr emit_hex_word
	bcc .failed
	jmp emit_newline
.failed:
	clc
	rts

rt_emit_bss_assignment:
	lda #rtBssAssignEnd-rtBssAssign
	ldx #<rtBssAssign
	ldy #>rtBssAssign
	jsr emit_text
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

;;; ---------------------------------------------------------------------------
;;; Generated test wrapper
;;;
;;; The wrapper sets decimal mode before one small C helper at a time. Each
;;; helper's first meaningful operation is the support/runtime call under test,
;;; including representative error returns. The helper performs the semantic
;;; check in Nano C and returns zero; .check_result also proves the call restored
;;; D=0. Keeping detailed checks in C avoids a second test-only runtime model.
;;; ---------------------------------------------------------------------------

rtHeader:
	string "* = $0800"
	string "NC_TMP = $fc"
	string "NC_PTR = $fe"
	string "NC_BSS = $3800"
	string "__nc_test_entry:"
	string "    sed"
	string "    jsr __nc_init"
	string "    jsr .check_d"
	string "    bcc .fail_init"

	string "    sed"
	string "    jsr __c_test_mul"
	string "    jsr .check_result"
	string "    bcc .fail_mul"
	string "    sed"
	string "    jsr __c_test_open"
	string "    jsr .check_result"
	string "    bcc .fail_open"
	string "    sed"
	string "    jsr __c_test_open_missing"
	string "    jsr .check_result"
	string "    bcc .fail_open_missing"
	string "    sed"
	string "    jsr __c_test_read"
	string "    jsr .check_result"
	string "    bcc .fail_read"
	string "    sed"
	string "    jsr __c_test_read_bad_handle"
	string "    jsr .check_result"
	string "    bcc .fail_read_bad"
	string "    sed"
	string "    jsr __c_test_close_read"
	string "    jsr .check_result"
	string "    bcc .fail_close_read"
	string "    sed"
	string "    jsr __c_test_create"
	string "    jsr .check_result"
	string "    bcc .fail_create"
	string "    sed"
	string "    jsr __c_test_create_bad_length"
	string "    jsr .check_result"
	string "    bcc .fail_create_bad"
	string "    sed"
	string "    jsr __c_test_write"
	string "    jsr .check_result"
	string "    bcc .fail_write"
	string "    sed"
	string "    jsr __c_test_write_bad_handle"
	string "    jsr .check_result"
	string "    bcc .fail_write_bad"
	string "    sed"
	string "    jsr __c_test_close_write"
	string "    jsr .check_result"
	string "    bcc .fail_close_write"
	string "    sed"
	string "    jsr __c_test_close_bad_handle"
	string "    jsr .check_result"
	string "    bcc .fail_close_bad"
	string "    jsr __c_main"
	string "    rts"

	string ".check_result:"
	string "    sta NC_TMP"
	string "    txa"
	string "    ora NC_TMP"
	string "    bne .bad_result"
	string ".check_d:"
	string "    php"
	string "    pla"
	string "    and #$08"
	string "    bne .bad_result"
	string "    sec"
	string "    rts"
	string ".bad_result:"
	string "    clc"
	string "    rts"

	string ".fail_init:"
	string "    lda #$40"
	string "    ldx #$00"
	string "    rts"
	string ".fail_mul:"
	string "    lda #$41"
	string "    ldx #$00"
	string "    rts"
	string ".fail_open:"
	string "    lda #$42"
	string "    ldx #$00"
	string "    rts"
	string ".fail_open_missing:"
	string "    lda #$43"
	string "    ldx #$00"
	string "    rts"
	string ".fail_read:"
	string "    lda #$44"
	string "    ldx #$00"
	string "    rts"
	string ".fail_read_bad:"
	string "    lda #$45"
	string "    ldx #$00"
	string "    rts"
	string ".fail_close_read:"
	string "    lda #$46"
	string "    ldx #$00"
	string "    rts"
	string ".fail_create:"
	string "    lda #$47"
	string "    ldx #$00"
	string "    rts"
	string ".fail_create_bad:"
	string "    lda #$48"
	string "    ldx #$00"
	string "    rts"
	string ".fail_write:"
	string "    lda #$49"
	string "    ldx #$00"
	string "    rts"
	string ".fail_write_bad:"
	string "    lda #$4a"
	string "    ldx #$00"
	string "    rts"
	string ".fail_close_write:"
	string "    lda #$4b"
	string "    ldx #$00"
	string "    rts"
	string ".fail_close_bad:"
	string "    lda #$4c"
	string "    ldx #$00"
	string "    rts"
	byte 0

rtBytePrefix:		byte $09,'b','y','t','e',' ','$'
rtBytePrefixEnd:
rtBssAssign:		byte ' ','=',' ','N','C','_','B','S','S','+','$'
rtBssAssignEnd:
rtBssEndPrefix:	byte '_','_','n','c','_','b','s','s','_','e','n','d',' ','=',' ','N','C','_','B','S','S','+','$'
rtBssEndPrefixEnd:

runtimeName:	byte 'R','U','N','T','I','M','E','.','C'
runtimeNameEnd:
outputName:	byte 'R','T','O','U','T','.','A','S','M',',','S',',','W'
outputNameEnd:

rtOutputOpen:	byte 0
rtDiagnostic:	byte 0
rtStorageKind:	byte 0
rtSavedSymbol:	byte 0
rtStaticByte:	byte 0

	include "declarations.asm"
	include "runtime_codegen.asm"
