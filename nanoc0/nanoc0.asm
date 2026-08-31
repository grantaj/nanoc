;;; nanoc0.asm
;;;
;;; Production assembly-written Nano C Phase 1 compiler.
;;;
;;; One native command block names the source and output files. The compiler
;;; streams source from device 8 and `ass` text to device 9; it never retains the
;;; translation unit or generated program. The generated machine map is fixed and
;;; deliberately visible:
;;;
;;;   $0800-$47ff  loaded code/static data, bounded by ass's 16 KiB staging area
;;;   $4800-$cfff  NC_BSS static workspace
;;;   $d000-$ffff  C64 I/O/KERNAL, left visible
;;;
;;; A generated unit begins with a fixed jump at $0800. If the source defines a
;;; zero-argument `main`, that entry initializes Nano C state and calls it. With
;;; no `main` it only initializes and returns; machine-specific wrappers can call
;;; the generated C functions directly by their readable assembler labels.

	include "interface.inc"

NANOC0_FIXED_WORKSPACE = 1
NANOC_SOURCE_DEVICE = 8
NANOC_OUTPUT_DEVICE = 9
NANOC_TARGET_ORIGIN = $0800
NANOC_TARGET_BSS    = $4800
NANOC_TARGET_LIMIT  = $d000

	* = $4000

nanoc0Entry:
	lda #$00
	sta NANOC_COMMAND_STATUS
	sta NANOC_COMMAND_DETAIL
	sta NANOC_COMMAND_LINE
	sta NANOC_COMMAND_LINE+1
	sta NANOC_COMMAND_BSS_BYTES
	sta NANOC_COMMAND_BSS_BYTES+1
	sta compilerOutputOpen
	sta emitOutputEnabled

	lda #<NANOC_TARGET_BSS
	sta bssBase
	lda #>NANOC_TARGET_BSS
	sta bssBase+1

	lda NANOC_COMMAND_SOURCE
	sta sourceName
	lda NANOC_COMMAND_SOURCE+1
	sta sourceName+1
	lda NANOC_COMMAND_SOURCE_LENGTH
	sta sourceNameLength
	lda #NANOC_SOURCE_DEVICE
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	jsr open_source
	bcs .sourceOpen
	jmp .sourceFailed
.sourceOpen:

	jsr open_compiler_output
	bcs .outputOpen
	jmp .outputFailed
.outputOpen:

	ldx #<programHeader
	ldy #>programHeader
	jsr emit_runtime_lines
	bcs .headerEmitted
	jmp .emitFailed
.headerEmitted:

	jsr parse_translation_unit
	bcs .compiled
	jmp .compileFailed
.compiled:
	jsr record_bss_bytes
	jsr generated_layout_fits
	bcs .layoutFits
	jmp .layoutFailed
.layoutFits:
	jsr emit_program_entry
	bcs .entryEmitted
	jmp .emitFailed
.entryEmitted:

	jsr close_source
	jsr close_compiler_output
	lda #NANOC_STATUS_OK
	sta NANOC_COMMAND_STATUS
	lda #$00
	tax
	rts

.sourceFailed:
	lda #NANOC_STATUS_SOURCE
	sta NANOC_COMMAND_STATUS
	lda sourceState
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.outputFailed:
	lda #NANOC_STATUS_OUTPUT
	sta NANOC_COMMAND_STATUS
	lda compilerOutputStatus
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.compileFailed:
	jsr record_bss_bytes
	jsr record_current_line
	lda parserError
	cmp #PARSE_SCANNER_ERROR
	beq .scannerFailure
	cmp #PARSE_EXPRESSION_ERROR
	beq .expressionFailure
	cmp #PARSE_EMIT_ERROR
	beq .emitCompileFailure
	lda #NANOC_STATUS_PARSER
	sta NANOC_COMMAND_STATUS
	lda parserError
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.scannerFailure:
	lda #NANOC_STATUS_SCANNER
	sta NANOC_COMMAND_STATUS
	lda scannerError
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.expressionFailure:
	lda #NANOC_STATUS_EXPRESSION
	sta NANOC_COMMAND_STATUS
	lda expressionError
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.emitCompileFailure:
	lda #NANOC_STATUS_EMIT
	sta NANOC_COMMAND_STATUS
	lda emitOutputStatus
	bne .saveEmitDetail
	lda parserError
.saveEmitDetail:
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.emitFailed:
	jsr record_bss_bytes
	jsr record_current_line
	lda #NANOC_STATUS_EMIT
	sta NANOC_COMMAND_STATUS
	lda emitOutputStatus
	sta NANOC_COMMAND_DETAIL
	jmp compiler_failure_return

.layoutFailed:
	lda #NANOC_STATUS_LAYOUT
	sta NANOC_COMMAND_STATUS
	lda #$01
	sta NANOC_COMMAND_DETAIL

compiler_failure_return:
	jsr close_source
	jsr close_compiler_output
	lda NANOC_COMMAND_STATUS
	ldx #$00
	rts

;;; The KERNAL output stream remains open while source.asm and emit.asm switch the
;;; one IEC bus explicitly between input and output channels.
open_compiler_output:
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda NANOC_COMMAND_OUTPUT_LENGTH
	ldx NANOC_COMMAND_OUTPUT
	ldy NANOC_COMMAND_OUTPUT+1
	jsr SETNAM
	lda #EMIT_OUTPUT_LFN
	ldx #NANOC_OUTPUT_DEVICE
	ldy #EMIT_OUTPUT_LFN
	jsr SETLFS
	jsr OPEN
	bcs .failed
	lda #$01
	sta compilerOutputOpen
	sta emitOutputEnabled
	lda #$00
	sta compilerOutputStatus
	sec
	rts
.failed:
	jsr READST
	sta compilerOutputStatus
	clc
	rts

close_compiler_output:
	lda #$00
	sta emitOutputEnabled
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda compilerOutputOpen
	beq .done
	lda #EMIT_OUTPUT_LFN
	jsr CLOSE
	lda #$00
	sta compilerOutputOpen
.done:
	rts

record_current_line:
	lda currentTokenLine
	sta NANOC_COMMAND_LINE
	lda currentTokenLine+1
	sta NANOC_COMMAND_LINE+1
	rts

record_bss_bytes:
	lda bssOffset
	sta NANOC_COMMAND_BSS_BYTES
	lda bssOffset+1
	sta NANOC_COMMAND_BSS_BYTES+1
	rts

;;; Carry set when [NC_BSS, NC_BSS+bssOffset) stays below the $d000 I/O window.
;;; The loaded-image side of the map is independently bounded by ass's 16 KiB
;;; representation when the generated source is assembled.
generated_layout_fits:
	clc
	lda #<NANOC_TARGET_BSS
	adc bssOffset
	sta generatedBssEnd
	lda #>NANOC_TARGET_BSS
	adc bssOffset+1
	sta generatedBssEnd+1
	bcs .failed
	lda generatedBssEnd+1
	cmp #>NANOC_TARGET_LIMIT
	bcc .fits
	bne .failed
	lda generatedBssEnd
	beq .fits
.failed:
	clc
	rts
.fits:
	sec
	rts

;;; The source language has no required `main`. The generated machine wrapper
;;; merely makes the common zero-argument main case convenient for complete
;;; native tests while leaving library-like translation units usable.
emit_program_entry:
	jsr source_has_zero_arg_main
	bcc .plain
	ldx #<programMainEntry
	ldy #>programMainEntry
	jmp emit_runtime_lines
.plain:
	ldx #<programPlainEntry
	ldy #>programPlainEntry
	jmp emit_runtime_lines

source_has_zero_arg_main:
	lda #$04
	sta currentTokenLength
	lda #'m'
	sta currentTokenText
	lda #'a'
	sta currentTokenText+1
	lda #'i'
	sta currentTokenText+2
	lda #'n'
	sta currentTokenText+3
	jsr lookup_persistent_token
	bcc .no
	lda persistentKind,x
	cmp #SYMBOL_FUNCTION
	bne .no
	lda persistentParamCount,x
	bne .no
	sec
	rts
.no:
	clc
	rts

programHeader:
	string "* = $0800"
	string "NC_TMP = $fc"
	string "NC_PTR = $fe"
	string "NC_BSS = $4800"
	string "__nc_start:"
	string "    jmp __nc_entry"
	byte 0

programMainEntry:
	string "__nc_entry:"
	string "    jsr __nc_init"
	string "    jsr __c_main"
	string "    rts"
	byte 0

programPlainEntry:
	string "__nc_entry:"
	string "    jsr __nc_init"
	string "    lda #$00"
	string "    tax"
	string "    rts"
	byte 0

compilerOutputOpen:	byte 0
compilerOutputStatus:	byte 0
generatedBssEnd:	word 0

	include "program_output.asm"
	include "declarations.asm"
	include "runtime_codegen.asm"
