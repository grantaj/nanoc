	include "../test.inc"

;;; Final #58 bootstrap proof.
;;;
;;; This low-memory driver survives both generated regions:
;;;
;;;   $0800-$47ff  loaded Nano C program
;;;   $4800-$cfff  Nano C BSS
;;;
;;; The production native assembler remains at $4000 just long enough to assemble
;;; ASSFROMC.ASM and expose its symbol table. Before the generated initializer can
;;; overwrite it, we copy those 6905 oracle bytes into RAM hidden under I/O/KERNAL
;;; at $d000. The compiled C assembler then assembles ASS/ASS_4000.ASM and its raw
;;; image is compared byte for byte with that untouched native oracle.
;;;
;;; No host code interprets compiler state here. `ass` resolves the generated
;;; labels; this driver merely writes their concrete 16-bit slots and patches the
;;; one JSR target a 6502 cannot indirect through memory.

GENERATED_BASE = $0800
ORACLE_BASE    = $4000
ORACLE_COPY    = $d000

BOOT_STAGE  = $03
BOOT_DETAIL = $04
BOOT_SIZE   = $05                 ; word: loaded ass-from-c image
BOOT_VALUE  = $07                 ; word: returned/observed value

STAGE_ASSEMBLE = 1
STAGE_SYMBOLS  = 2
STAGE_RUN      = 3
STAGE_COMPARE  = 4

FAIL_ASSEMBLE = $11
FAIL_SYMBOL   = $12
FAIL_RUN      = $13
FAIL_LENGTH   = $14
FAIL_ORIGIN   = $15
FAIL_BYTES    = $16

	* = $0200

main:
	lda #$00
	sta BOOT_STAGE
	sta BOOT_DETAIL
	sta BOOT_SIZE
	sta BOOT_SIZE+1
	sta BOOT_VALUE
	sta BOOT_VALUE+1

	;;; current native ass -> compiler-generated ass source -> executable at $0800
	lda #<generatedSource
	sta ASSEMBLER_COMMAND_NAME
	lda #>generatedSource
	sta ASSEMBLER_COMMAND_NAME+1
	lda #generatedSourceEnd-generatedSource
	sta ASSEMBLER_COMMAND_LENGTH
	lda #<GENERATED_BASE
	sta ASSEMBLER_COMMAND_TARGET
	lda #>GENERATED_BASE
	sta ASSEMBLER_COMMAND_TARGET+1
	lda #STAGE_ASSEMBLE
	sta BOOT_STAGE
	jsr assemblerEntry
	beq .assembled
	sta BOOT_DETAIL
	lda #FAIL_ASSEMBLE
	jmp finish

.assembled:
	;;; assemblyPtr is still the native assembler's final target pointer.
	sec
	lda assemblyPtr
	sbc #<GENERATED_BASE
	sta BOOT_SIZE
	lda assemblyPtr+1
	sbc #>GENERATED_BASE
	sta BOOT_SIZE+1

	;;; The symbol table is also still live. Resolve every machine fact we need
	;;; before __nc_init is allowed to reuse $4800-$cfff as generated BSS.
	lda #STAGE_SYMBOLS
	sta BOOT_STAGE
	lda #assAssembleNameEnd-assAssembleName
	ldx #<assAssembleName
	ldy #>assAssembleName
	jsr find_generated_symbol
	bcc .symbol0
	lda symbolValue
	sta callAssAssemble+1
	lda symbolValue+1
	sta callAssAssemble+2

	lda #param0NameEnd-param0Name
	ldx #<param0Name
	ldy #>param0Name
	jsr find_generated_symbol
	bcc .symbol1
	lda symbolValue
	sta param0
	lda symbolValue+1
	sta param0+1

	lda #param1NameEnd-param1Name
	ldx #<param1Name
	ldy #>param1Name
	jsr find_generated_symbol
	bcc .symbol2
	lda symbolValue
	sta param1
	lda symbolValue+1
	sta param1+1

	lda #param2NameEnd-param2Name
	ldx #<param2Name
	ldy #>param2Name
	jsr find_generated_symbol
	bcc .symbol3
	lda symbolValue
	sta param2
	lda symbolValue+1
	sta param2+1

	lda #param3NameEnd-param3Name
	ldx #<param3Name
	ldy #>param3Name
	jsr find_generated_symbol
	bcc .symbol4
	lda symbolValue
	sta param3
	lda symbolValue+1
	sta param3+1

	lda #param4NameEnd-param4Name
	ldx #<param4Name
	ldy #>param4Name
	jsr find_generated_symbol
	bcc .symbol5
	lda symbolValue
	sta param4
	lda symbolValue+1
	sta param4+1

	lda #assImageNameEnd-assImageName
	ldx #<assImageName
	ldy #>assImageName
	jsr find_generated_symbol
	bcc .symbol6
	lda symbolValue
	sta generatedImage
	lda symbolValue+1
	sta generatedImage+1

	lda #assLengthNameEnd-assLengthName
	ldx #<assLengthName
	ldy #>assLengthName
	jsr find_generated_symbol
	bcc .symbol7
	lda symbolValue
	sta generatedLength
	lda symbolValue+1
	sta generatedLength+1

	lda #assOriginNameEnd-assOriginName
	ldx #<assOriginName
	ldy #>assOriginName
	jsr find_generated_symbol
	bcc .symbol8
	lda symbolValue
	sta generatedOrigin
	lda symbolValue+1
	sta generatedOrigin+1
	jmp .symbolsReady

.symbol0:
	lda #0
	jmp symbol_fail
.symbol1:
	lda #1
	jmp symbol_fail
.symbol2:
	lda #2
	jmp symbol_fail
.symbol3:
	lda #3
	jmp symbol_fail
.symbol4:
	lda #4
	jmp symbol_fail
.symbol5:
	lda #5
	jmp symbol_fail
.symbol6:
	lda #6
	jmp symbol_fail
.symbol7:
	lda #7
	jmp symbol_fail
.symbol8:
	lda #8
symbol_fail:
	sta BOOT_DETAIL
	lda #FAIL_SYMBOL
	jmp finish

.symbolsReady:
	jsr copy_native_oracle

	;;; A generated unit without main has one fixed public entry: initialize its
	;;; C storage/runtime, then return. After this call the old native assembler and
	;;; symbol table may have been overwritten; all required addresses are low now.
	lda #STAGE_RUN
	sta BOOT_STAGE
	jsr GENERATED_BASE

	lda param0
	sta ZP_PTR0
	lda param0+1
	sta ZP_PTR0+1
	lda #<rootName
	ldx #>rootName
	jsr store_word

	lda param1
	sta ZP_PTR0
	lda param1+1
	sta ZP_PTR0+1
	lda #rootNameEnd-rootName
	ldx #$00
	jsr store_word

	lda param2
	sta ZP_PTR0
	lda param2+1
	sta ZP_PTR0+1
	lda #<bootstrapSourceDirectory
	ldx #>bootstrapSourceDirectory
	jsr store_word

	lda param3
	sta ZP_PTR0
	lda param3+1
	sta ZP_PTR0+1
	lda #bootstrapSourceDirectoryEnd-bootstrapSourceDirectory
	ldx #$00
	jsr store_word

	lda param4
	sta ZP_PTR0
	lda param4+1
	sta ZP_PTR0+1
	lda #$00
	ldx #$00
	jsr store_word

callAssAssemble:
	jsr $ffff
	sta BOOT_VALUE
	stx BOOT_VALUE+1
	ora BOOT_VALUE+1
	beq .ran
	lda #FAIL_RUN
	jmp finish

.ran:
	lda #STAGE_COMPARE
	sta BOOT_STAGE

	;;; ass_image_length must describe exactly the established production image.
	lda generatedLength
	sta ZP_PTR0
	lda generatedLength+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	sta BOOT_VALUE
	cmp #<ORACLE_BYTES
	bne .badLength
	iny
	lda (ZP_PTR0),y
	sta BOOT_VALUE+1
	cmp #>ORACLE_BYTES
	bne .badLength

	;;; The production source itself chooses $4000, just as in the host oracle.
	lda generatedOrigin
	sta ZP_PTR0
	lda generatedOrigin+1
	sta ZP_PTR0+1
	ldy #$00
	lda (ZP_PTR0),y
	sta BOOT_VALUE
	cmp #<ORACLE_BASE
	bne .badOrigin
	iny
	lda (ZP_PTR0),y
	sta BOOT_VALUE+1
	cmp #>ORACLE_BASE
	bne .badOrigin

	jsr compare_with_oracle
	bcs .pass
	lda #FAIL_BYTES
	jmp finish
.badLength:
	lda #FAIL_LENGTH
	jmp finish
.badOrigin:
	lda #FAIL_ORIGIN
	jmp finish
.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; A=length, X/Y=address. Only ordinary generated labels are accepted; an
;;; unresolved label at this point would mean the native assembly was not whole.
find_generated_symbol:
	sta symbolNameLength
	stx symbolName
	sty symbolName+1
	jsr findSymbolEntry
	bcc .failed
	lda symbolKind
	cmp #SYMBOL_LABEL_DEFINED
	beq .ok
	cmp #SYMBOL_CONSTANT
	beq .ok
.failed:
	clc
	rts
.ok:
	sec
	rts

;;; ZP_PTR0=destination, A/X=low/high word.
store_word:
	ldy #$00
	sta (ZP_PTR0),y
	iny
	txa
	sta (ZP_PTR0),y
	rts

;;; Save the known-good production assembler in physical RAM under the C64 ROMs.
;;; Interrupts stay off only while the KERNAL vectors are hidden.
copy_native_oracle:
	sei
	lda $01
	sta savedMemoryMap
	lda #$34
	sta $01
	lda #<ORACLE_BASE
	sta ZP_PTR0
	lda #>ORACLE_BASE
	sta ZP_PTR0+1
	lda #<ORACLE_COPY
	sta ZP_PTR1
	lda #>ORACLE_COPY
	sta ZP_PTR1+1
	lda #<ORACLE_BYTES
	sta bytesLeft
	lda #>ORACLE_BYTES
	sta bytesLeft+1
	jsr copy_bytes
	lda savedMemoryMap
	sta $01
	cli
	rts

;;; Compare generated ass_image with the hidden native oracle. No KERNAL service
;;; is needed after ass_assemble has returned, so the comparison can safely expose
;;; RAM at $d000 for its whole duration.
compare_with_oracle:
	sei
	lda $01
	sta savedMemoryMap
	lda #$34
	sta $01
	lda generatedImage
	sta ZP_PTR0
	lda generatedImage+1
	sta ZP_PTR0+1
	lda #<ORACLE_COPY
	sta ZP_PTR1
	lda #>ORACLE_COPY
	sta ZP_PTR1+1
	lda #<ORACLE_BYTES
	sta bytesLeft
	lda #>ORACLE_BYTES
	sta bytesLeft+1
	ldy #$00
.loop:
	lda bytesLeft
	ora bytesLeft+1
	beq .same
	lda (ZP_PTR0),y
	cmp (ZP_PTR1),y
	bne .different
	jsr advance_copy_pointers
	jsr decrement_bytes_left
	jmp .loop
.same:
	lda savedMemoryMap
	sta $01
	cli
	sec
	rts
.different:
	lda savedMemoryMap
	sta $01
	cli
	clc
	rts

copy_bytes:
	ldy #$00
.loop:
	lda bytesLeft
	ora bytesLeft+1
	beq .done
	lda (ZP_PTR0),y
	sta (ZP_PTR1),y
	jsr advance_copy_pointers
	jsr decrement_bytes_left
	jmp .loop
.done:
	rts

advance_copy_pointers:
	inc ZP_PTR0
	bne .destination
	inc ZP_PTR0+1
.destination:
	inc ZP_PTR1
	bne .done
	inc ZP_PTR1+1
.done:
	rts

decrement_bytes_left:
	lda bytesLeft
	bne .low
	dec bytesLeft+1
.low:
	dec bytesLeft
	rts

generatedSource:
	byte 'B','U','I','L','D','/','N','A','N','O','C','0','-','I','N','T','E','G','R','A','T','I','O','N','/','A','S','S','F','R','O','M','C','.','A','S','M'
generatedSourceEnd:
rootName:
	byte 'A','S','S','/','A','S','S','_','4','0','0','0','.','A','S','M'
rootNameEnd:
bootstrapSourceDirectory:
	byte 'A','S','S','/'
bootstrapSourceDirectoryEnd:

assAssembleName:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e'
assAssembleNameEnd:
param0Name:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e','_','_','v','0','0'
param0NameEnd:
param1Name:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e','_','_','v','0','1'
param1NameEnd:
param2Name:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e','_','_','v','0','2'
param2NameEnd:
param3Name:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e','_','_','v','0','3'
param3NameEnd:
param4Name:	byte '_','_','c','_','a','s','s','_','a','s','s','e','m','b','l','e','_','_','v','0','4'
param4NameEnd:
assImageName:	byte '_','_','c','_','a','s','s','_','i','m','a','g','e'
assImageNameEnd:
assLengthName:	byte '_','_','c','_','a','s','s','_','i','m','a','g','e','_','l','e','n','g','t','h'
assLengthNameEnd:
assOriginName:	byte '_','_','c','_','a','s','s','_','o','r','i','g','i','n'
assOriginNameEnd:

param0:		word 0
param1:		word 0
param2:		word 0
param3:		word 0
param4:		word 0
generatedImage:	word 0
generatedLength:	word 0
generatedOrigin:	word 0
bytesLeft:	word 0
savedMemoryMap:	byte 0

	* = ORACLE_BASE
	include "ass.asm"
oracleAssEnd:

ORACLE_BYTES = oracleAssEnd-ORACLE_BASE