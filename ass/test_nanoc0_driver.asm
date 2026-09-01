	include "../test.inc"
	include "../nanoc0/interface.inc"

NANOC0_IMAGE = $4000

FAIL_BUILD_NANOC0  = $10
FAIL_COMPILE_SOURCE = $20
FAIL_COMPILE_ASS    = $30

;;; Small integration mailbox saved by tests/run-test.sh along with TEST_RESULT.
;;; It is diagnostic/reporting state only; the result byte remains authoritative.
INTEGRATION_STAGE  = $03
INTEGRATION_STATUS = $04
INTEGRATION_LINE   = $05
INTEGRATION_DETAIL = $07
INTEGRATION_BSS    = $08
INTEGRATION_EXTRA  = $0a
INTEGRATION_HIDDEN = $0b

STAGE_BUILD_NANOC0  = 1
STAGE_COMPILE_SOURCE = 2
STAGE_COMPILE_ASS    = 3

	* = $0800

main:
	lda #$00
	sta INTEGRATION_STAGE
	sta INTEGRATION_STATUS
	sta INTEGRATION_LINE
	sta INTEGRATION_LINE+1
	sta INTEGRATION_DETAIL
	sta INTEGRATION_BSS
	sta INTEGRATION_BSS+1
	sta INTEGRATION_EXTRA
	sta INTEGRATION_HIDDEN
	sta INTEGRATION_HIDDEN+1

	;;; Use the production assembler machinery at low memory to assemble the
	;;; production nanoc0 source tree into $4000. assemblerEntry itself fixes its
	;;; include root to ASS/ for self-hosting, so this test supplies the already-
	;;; supported sourceDirectory inputs directly as NANOC0/.
	lda #<ASSEMBLER_SYMBOLS
	sta symbolTableStart
	lda #>ASSEMBLER_SYMBOLS
	sta symbolTableStart+1
	lda #<ASSEMBLER_SYMBOLS_END
	sta symbolTableLimit
	lda #>ASSEMBLER_SYMBOLS_END
	sta symbolTableLimit+1

	lda #<ASSEMBLER_LOCAL_SYMBOLS
	sta localSymbolTableStart
	lda #>ASSEMBLER_LOCAL_SYMBOLS
	sta localSymbolTableStart+1
	lda #<ASSEMBLER_LOCAL_SYMBOLS_END
	sta localSymbolTableLimit
	lda #>ASSEMBLER_LOCAL_SYMBOLS_END
	sta localSymbolTableLimit+1

	;;; The ladder uses exactly the production persistent ranges, including the
	;;; final physical-RAM arena underneath I/O/KERNAL.
	lda #<ASSEMBLER_SYMBOL_OVERFLOW
	sta symbolOverflowStart
	lda #>ASSEMBLER_SYMBOL_OVERFLOW
	sta symbolOverflowStart+1
	lda #<ASSEMBLER_SYMBOL_OVERFLOW_END
	sta symbolOverflowLimit
	lda #>ASSEMBLER_SYMBOL_OVERFLOW_END
	sta symbolOverflowLimit+1
	lda #<ASSEMBLER_SYMBOL_HIDDEN
	sta symbolHiddenStart
	lda #>ASSEMBLER_SYMBOL_HIDDEN
	sta symbolHiddenStart+1
	lda #<ASSEMBLER_SYMBOL_HIDDEN_END
	sta symbolHiddenLimit
	lda #>ASSEMBLER_SYMBOL_HIDDEN_END
	sta symbolHiddenLimit+1

	lda #<ASSEMBLER_STAGING
	sta stagingStart
	lda #>ASSEMBLER_STAGING
	sta stagingStart+1
	lda #<ASSEMBLER_STAGING_END
	sta stagingLimit
	lda #>ASSEMBLER_STAGING_END
	sta stagingLimit+1

	lda #<nanoc0Name
	sta sourceName
	lda #>nanoc0Name
	sta sourceName+1
	lda #nanoc0NameEnd-nanoc0Name
	sta sourceNameLength
	lda #$08
	sta sourceDevice
	lda #<ASSEMBLER_LINE_BUFFER
	sta sourceLineBuffer
	lda #>ASSEMBLER_LINE_BUFFER
	sta sourceLineBuffer+1
	lda #<nanoc0Directory
	sta sourceDirectory
	lda #>nanoc0Directory
	sta sourceDirectory+1
	lda #nanoc0DirectoryEnd-nanoc0Directory
	sta sourceDirectoryLength
	lda #<ASSEMBLER_PATH_BUFFER
	sta sourcePathBuffer
	lda #>ASSEMBLER_PATH_BUFFER
	sta sourcePathBuffer+1
	lda #<NANOC0_IMAGE
	sta assemblyPtr
	lda #>NANOC0_IMAGE
	sta assemblyPtr+1

	lda #STAGE_BUILD_NANOC0
	sta INTEGRATION_STAGE
	jsr assembleFile
	sta INTEGRATION_STATUS
	cmp #ASSEMBLE_OK
	beq .compilerReady
	jsr capture_ass_workspace
	lda INTEGRATION_STATUS
	ora #FAIL_BUILD_NANOC0
	jmp finish

.compilerReady:
	;;; Keep one deliberately small complete program in front of the bootstrap.
	;;; It catches entry/output regressions without making ass.c the first symptom.
	lda #<smallSourceName
	sta NANOC_COMMAND_SOURCE
	lda #>smallSourceName
	sta NANOC_COMMAND_SOURCE+1
	lda #smallSourceNameEnd-smallSourceName
	sta NANOC_COMMAND_SOURCE_LENGTH
	lda #<smallOutputName
	sta NANOC_COMMAND_OUTPUT
	lda #>smallOutputName
	sta NANOC_COMMAND_OUTPUT+1
	lda #smallOutputNameEnd-smallOutputName
	sta NANOC_COMMAND_OUTPUT_LENGTH
	lda #STAGE_COMPILE_SOURCE
	sta INTEGRATION_STAGE
	jsr NANOC0_IMAGE
	jsr capture_nanoc_result
	lda NANOC_COMMAND_STATUS
	beq .smallReady
	ora #FAIL_COMPILE_SOURCE
	jmp finish

.smallReady:
	;;; The decisive source is the exact committed bootstrap/ass.c. No adapter or
	;;; compiler-specific C copy sits between nanoc0 and this file.
	lda #<assSourceName
	sta NANOC_COMMAND_SOURCE
	lda #>assSourceName
	sta NANOC_COMMAND_SOURCE+1
	lda #assSourceNameEnd-assSourceName
	sta NANOC_COMMAND_SOURCE_LENGTH
	lda #<assOutputName
	sta NANOC_COMMAND_OUTPUT
	lda #>assOutputName
	sta NANOC_COMMAND_OUTPUT+1
	lda #assOutputNameEnd-assOutputName
	sta NANOC_COMMAND_OUTPUT_LENGTH
	lda #STAGE_COMPILE_ASS
	sta INTEGRATION_STAGE
	jsr NANOC0_IMAGE
	jsr capture_nanoc_result
	lda NANOC_COMMAND_STATUS
	beq .pass
	ora #FAIL_COMPILE_ASS
	jmp finish
.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; On an assembler-stage failure the compiler diagnostic fields are not live yet.
;;; For symbol pressure the line word carries the first persistent end, the BSS
;;; word carries the local end, DETAIL/EXTRA carry the visible shared end, and
;;; HIDDEN carries the physical-RAM persistent end. For work pressure they carry
;;; the staged-image and fixup cursors instead. These are direct measurements of
;;; the fixed C64 workspaces; no host model is involved.
capture_ass_workspace:
	lda INTEGRATION_STATUS
	cmp #ASSEMBLE_WORK_FULL
	beq .work
	lda symbolTableEnd
	sta INTEGRATION_LINE
	lda symbolTableEnd+1
	sta INTEGRATION_LINE+1
	lda symbolOverflowEnd
	sta INTEGRATION_DETAIL
	lda symbolOverflowEnd+1
	sta INTEGRATION_EXTRA
	lda localSymbolTableEnd
	sta INTEGRATION_BSS
	lda localSymbolTableEnd+1
	sta INTEGRATION_BSS+1
	lda symbolHiddenEnd
	sta INTEGRATION_HIDDEN
	lda symbolHiddenEnd+1
	sta INTEGRATION_HIDDEN+1
	rts
.work:
	lda stagingPtr
	sta INTEGRATION_LINE
	lda stagingPtr+1
	sta INTEGRATION_LINE+1
	lda currentScope
	sta INTEGRATION_DETAIL
	lda #$00
	sta INTEGRATION_EXTRA
	sta INTEGRATION_HIDDEN
	sta INTEGRATION_HIDDEN+1
	lda fixupFree
	sta INTEGRATION_BSS
	lda fixupFree+1
	sta INTEGRATION_BSS+1
	rts

;;; Preserve the production compiler command result in low RAM before the next
;;; operation can reuse the command block. These are exactly the facts a person
;;; needs when the native ladder fails, plus BSS bytes for the successful build.
capture_nanoc_result:
	lda NANOC_COMMAND_STATUS
	sta INTEGRATION_STATUS
	lda NANOC_COMMAND_LINE
	sta INTEGRATION_LINE
	lda NANOC_COMMAND_LINE+1
	sta INTEGRATION_LINE+1
	lda NANOC_COMMAND_DETAIL
	sta INTEGRATION_DETAIL
	lda #$00
	sta INTEGRATION_EXTRA
	sta INTEGRATION_HIDDEN
	sta INTEGRATION_HIDDEN+1
	lda NANOC_COMMAND_BSS_BYTES
	sta INTEGRATION_BSS
	lda NANOC_COMMAND_BSS_BYTES+1
	sta INTEGRATION_BSS+1
	rts

nanoc0Name:
	byte 'N','A','N','O','C','0','/','N','A','N','O','C','0','.','A','S','M'
nanoc0NameEnd:
nanoc0Directory:
	byte 'N','A','N','O','C','0','/'
nanoc0DirectoryEnd:
smallSourceName:
	byte 'T','E','S','T','S','/','N','A','N','O','C','0','-','S','T','M','T','/','R','E','T','U','R','N','8','.','C'
smallSourceNameEnd:
smallOutputName:
	byte 'N','C','O','U','T','.','A','S','M',',','S',',','W'
smallOutputNameEnd:
assSourceName:
	byte 'B','O','O','T','S','T','R','A','P','/','A','S','S','.','C'
assSourceNameEnd:
assOutputName:
	byte 'A','S','S','F','R','O','M','C','.','A','S','M',',','S',',','W'
assOutputNameEnd:

	include "ass.asm"
