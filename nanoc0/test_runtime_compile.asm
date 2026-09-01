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
;;; Generated test wrapper
;;;
;;; The wrapper sets decimal mode before one small C helper at a time. Each
;;; helper's first meaningful operation is the support/runtime call under test.
;;; Missing-file open and invalid-handle read deliberately cover error returns;
;;; the helper checks the result in Nano C and .check_result proves D=0.
;;;
;;; Declaration and runtime-support output below comes from program_output.asm,
;;; exactly as it does in production nanoc0. Only this acceptance-test wrapper
;;; is special.
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
	string "    jsr __c_test_write"
	string "    jsr .check_result"
	string "    bcc .fail_write"
	string "    sed"
	string "    jsr __c_test_close_write"
	string "    jsr .check_result"
	string "    bcc .fail_close_write"
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
	string ".fail_write:"
	string "    lda #$48"
	string "    ldx #$00"
	string "    rts"
	string ".fail_close_write:"
	string "    lda #$49"
	string "    ldx #$00"
	string "    rts"
	byte 0

runtimeName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','R','U','N','T','I','M','E','/','R','U','N','T','I','M','E','.','C'
runtimeNameEnd:
outputName:	byte 'R','T','O','U','T','.','A','S','M',',','S',',','W'
outputNameEnd:

rtOutputOpen:	byte 0
rtDiagnostic:	byte 0

	include "declarations.asm"
	include "program_output.asm"
	include "runtime_codegen.asm"
