	include "../test.inc"
	include "../nanoc0/interface.inc"

NANOC0_IMAGE = $4000

FAIL_BUILD_NANOC0  = $10
FAIL_COMPILE_SOURCE = $20
FAIL_COMPILE_ASS    = $30

	* = $0800

main:
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

	jsr assembleFile
	cmp #ASSEMBLE_OK
	beq .compilerReady
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
	jsr NANOC0_IMAGE
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
	jsr NANOC0_IMAGE
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
