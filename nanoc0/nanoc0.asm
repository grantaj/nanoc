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
NANOC_TARGET_BSS_LIMIT = NANOC_TARGET_LIMIT-NANOC_TARGET_BSS

	* = $4000

;;; Keep the native command entry fixed while putting the compiler modules first
;;; in source order. That matters to ass: constants such as the KERNAL jump-table
;;; names are then defined before compilerMain uses them.
;;;
;;; The compiler's bounded work RAM uses the area under BASIC ROM. Like ass, the
;;; public native entry therefore owns the C64 memory map explicitly: BASIC is
;;; hidden while KERNAL and I/O remain visible, then the caller's $01 value is
;;; restored. The caller's mapping lives beneath compiler call frames on the
;;; hardware stack; X preserves the returned status while that byte is restored.
;;; The hardware stack is never C storage.
nanoc0Entry:
	lda $01
	pha
	lda #$36
	sta $01
	jsr compilerMain
	tax
	pla
	sta $01
	txa
	rts

	include "declarations.asm"
	include "runtime_codegen.asm"
	include "program_output.asm"

;;; Fixed generated-program text and the driver's tiny private state are kept
;;; before the routines that name them. Native ass is one-pass, so fixed data has
;;; no reason to consume forward-fixup workspace while the compiler is assembled.
;;; emit_runtime_lines writes these bytes verbatim; tabs inside instruction
;;; strings are therefore real output tabs.
programHeader:
	string "* = $0800"
	string "NC_TMP = $fc"
	string "NC_PTR = $fe"
	string "NC_BSS = $4800"
	string "__nc_start:"
	string "	jmp __nc_entry"
	byte 0

programEntryPrefix:
	string "__nc_entry:"
	string "	jsr __nc_init"
	byte 0

programMainEntry:
	string "	jsr __c_main"
	string "	rts"
	byte 0

programPlainEntry:
	string "	lda #$00"
	string "	tax"
	string "	rts"
	byte 0

compilerMain:
	lda #$00
	ldy #$05
.clearCommandResult:
	sta NANOC_COMMAND_STATUS,y
	dey
	bpl .clearCommandResult
	sta emitOutputEnabled
	sta emitOutputStatus

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
	tax
	rts

.sourceFailed:
	lda sourceState
	ldx #NANOC_STATUS_SOURCE
	jmp compiler_failure

.outputFailed:
	lda emitOutputStatus
	ldx #NANOC_STATUS_OUTPUT
	jmp compiler_failure

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
	lda parserError
	ldx #NANOC_STATUS_PARSER
	jmp compiler_failure

.scannerFailure:
	lda scannerError
	ldx #NANOC_STATUS_SCANNER
	jmp compiler_failure

.expressionFailure:
	lda expressionError
	ldx #NANOC_STATUS_EXPRESSION
	jmp compiler_failure

.emitCompileFailure:
	lda emitOutputStatus
	bne .haveEmitDetail
	lda parserError
.haveEmitDetail:
	ldx #NANOC_STATUS_EMIT
	jmp compiler_failure

.emitFailed:
	jsr record_bss_bytes
	jsr record_current_line
	lda emitOutputStatus
	ldx #NANOC_STATUS_EMIT
	jmp compiler_failure

.layoutFailed:
	lda #$01
	ldx #NANOC_STATUS_LAYOUT

;;; A=layer detail, X=NANOC_STATUS_*. All failures close both streams and return
;;; the broad status in A.
compiler_failure:
	sta NANOC_COMMAND_DETAIL
	stx NANOC_COMMAND_STATUS

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
	sta emitOutputEnabled
	sec
	rts
.failed:
	jsr READST
	sta emitOutputStatus
	clc
	rts

;;; emitOutputEnabled is also the ownership flag: it becomes nonzero only after
;;; this compiler has successfully opened its output logical file.
close_compiler_output:
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda emitOutputEnabled
	beq .done
	lda #$00
	sta emitOutputEnabled
	lda #EMIT_OUTPUT_LFN
	jsr CLOSE
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
	;;; Compare the offset itself: NC_BSS has exactly this much room before I/O.
	lda bssOffset+1
	cmp #>NANOC_TARGET_BSS_LIMIT
	bcc .fits
	bne .failed
	lda bssOffset
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
	ldx #<programEntryPrefix
	ldy #>programEntryPrefix
	jsr emit_runtime_lines
	bcc .failed
	jsr source_has_zero_arg_main
	bcc .plain
	ldx #<programMainEntry
	ldy #>programMainEntry
	jmp emit_runtime_lines
.plain:
	ldx #<programPlainEntry
	ldy #>programPlainEntry
	jmp emit_runtime_lines
.failed:
	clc
	rts

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
	bcs .found
.no:
	clc
	rts
.found:
	lda persistentKind,x
	cmp #SYMBOL_FUNCTION
	bne .no
	lda persistentParamCount,x
	bne .no
	sec
	rts
