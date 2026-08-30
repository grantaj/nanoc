	include "../test.inc"

FAIL_OPEN           = $01
FAIL_VALID_STATE    = $02
FAIL_VALID_DATA     = $03
FAIL_BSS_ONLY       = $04
FAIL_DUP_GLOBAL     = $05
FAIL_DUP_FUNCTION   = $06
FAIL_DUP_PARAMETER  = $07
FAIL_DUP_LOCAL      = $08
FAIL_LATE_GLOBAL    = $09
FAIL_LATE_LOCAL     = $0a
FAIL_SELF_LOCAL     = $0b
FAIL_FORWARD_LOCAL  = $0c
FAIL_LATER_FUNCTION = $0d
FAIL_SHADOW         = $0e
FAIL_TOO_MANY       = $0f
FAIL_STRING_FIT     = $10
FAIL_BSS_OVERFLOW   = $11
FAIL_CHAR_RANGE     = $12
FAIL_INT_RANGE      = $13

IDX_FLAG      = 5
IDX_COUNT     = 6
IDX_ADDRESS   = 7
IDX_SOURCE    = 8
IDX_C         = 9
IDX_NEG       = 10
IDX_U         = 11
IDX_BYTES     = 12
IDX_WORDS     = 13
IDX_ADDRESSES = 14
IDX_WIDTHS    = 15
IDX_TABLE     = 16
IDX_TEXT      = 17
IDX_HELPER    = 18
IDX_MAIN      = 19

;;; Declarations plus scanner/symbol state are intentionally exercised as one
;;; native image.  $4000 leaves a broad ordinary-RAM window for the bounded
;;; symbol/name areas without approaching C64 I/O space.
	* = $4000

main:
	jsr test_valid_translation
	bcs .bss
	jmp finish
.bss:
	jsr test_bss_only
	bcs .dupGlobal
	jmp finish
.dupGlobal:
	jsr test_duplicate_global
	bcs .dupFunction
	jmp finish
.dupFunction:
	jsr test_duplicate_function
	bcs .dupParameter
	jmp finish
.dupParameter:
	jsr test_duplicate_parameter
	bcs .dupLocal
	jmp finish
.dupLocal:
	jsr test_duplicate_local
	bcs .lateGlobal
	jmp finish
.lateGlobal:
	jsr test_late_global
	bcs .lateLocal
	jmp finish
.lateLocal:
	jsr test_late_local
	bcs .selfLocal
	jmp finish
.selfLocal:
	jsr test_self_local
	bcs .forwardLocal
	jmp finish
.forwardLocal:
	jsr test_forward_local
	bcs .laterFunction
	jmp finish
.laterFunction:
	jsr test_later_function
	bcs .shadow
	jmp finish
.shadow:
	jsr test_shadowing
	bcs .tooMany
	jmp finish
.tooMany:
	jsr test_too_many_initializers
	bcs .stringFit
	jmp finish
.stringFit:
	jsr test_string_fit
	bcs .bssOverflow
	jmp finish
.bssOverflow:
	jsr test_bss_overflow
	bcs .charRange
	jmp finish
.charRange:
	jsr test_char_range
	bcs .intRange
	jmp finish
.intRange:
	jsr test_int_range
	bcs .pass
	jmp finish
.pass:
	lda #TEST_PASS
finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; Comprehensive valid translation.  This fixture proves exact BSS widths,
;;; initialized-data streaming, function metadata, runtime-name lookup and local
;;; initializer visibility without a host-side declaration parser.
test_valid_translation:
	jsr set_default_bss
	lda #declsNameEnd-declsName
	ldx #<declsName
	ldy #>declsName
	jsr parse_fixture
	bcs .parsed
	lda #FAIL_OPEN
	ldx fixtureOpenFailed
	bne .fail
	lda #FAIL_VALID_STATE
.fail:
	clc
	rts
.parsed:
	lda parserError
	bne .stateFail
	lda persistentCount
	cmp #20
	bne .stateFail
	lda userFunctionCount
	cmp #2
	bne .stateFail
	lda currentCount
	bne .stateFail
	lda bssOffset
	cmp #$24
	bne .stateFail
	lda bssOffset+1
	bne .stateFail
	lda zeroRequiredEnd
	cmp #$13
	bne .stateFail
	lda zeroRequiredEnd+1
	bne .stateFail
	lda emittedPersistentCount
	cmp #15
	bne .stateFail
	lda emittedCurrentCount
	cmp #9
	bne .stateFail
	lda emittedBoundaryCount
	cmp #1
	bne .stateFail

	;; Runtime functions are ordinary predefined persistent function entries.
	lda persistentKind
	cmp #SYMBOL_RUNTIME_FUNCTION
	bne .stateFail
	lda persistentParamCount
	cmp #2
	bne .stateFail
	lda persistentParamCount+3
	cmp #2
	bne .stateFail

	;; Exact uninitialized-global BSS layout: char=1, all 16-bit forms=2.
	lda persistentKind+IDX_FLAG
	cmp #SYMBOL_GLOBAL_BSS
	bne .stateFail
	lda persistentType+IDX_FLAG
	cmp #TYPE_CHAR
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_FLAG
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_COUNT
	cmp #1
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_ADDRESS
	cmp #3
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_SOURCE
	cmp #5
	bne .stateFail
	lda persistentType+IDX_SOURCE
	cmp #TYPE_CHAR_PTR
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_BYTES
	cmp #7
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_WORDS
	cmp #11
	bne .stateFail
	lda persistentStorageOffsetLo+IDX_ADDRESSES
	cmp #15
	bne .stateFail
	lda persistentArrayLengthLo+IDX_WORDS
	cmp #2
	bne .stateFail

	;; Initialized globals live in loaded data rather than consuming NC_BSS.
	lda persistentKind+IDX_C
	cmp #SYMBOL_GLOBAL_DATA
	bne .stateFail
	lda persistentKind+IDX_WIDTHS
	cmp #SYMBOL_ARRAY_DATA
	bne .stateFail
	lda persistentArrayLengthLo+IDX_TEXT
	cmp #5
	bne .stateFail

	;; helper(char p,unsigned q,char *s): metadata survives current-table reuse.
	lda persistentKind+IDX_HELPER
	cmp #SYMBOL_FUNCTION
	bne .stateFail
	lda persistentParamStart+IDX_HELPER
	cmp #8
	bne .stateFail
	lda persistentParamCount+IDX_HELPER
	cmp #3
	bne .stateFail
	lda parameterType+8
	cmp #TYPE_CHAR
	bne .stateFail
	lda parameterStorageOffsetLo+8
	cmp #$13
	bne .stateFail
	lda parameterType+9
	cmp #TYPE_UNSIGNED
	bne .stateFail
	lda parameterStorageOffsetLo+9
	cmp #$14
	bne .stateFail
	lda parameterType+10
	cmp #TYPE_CHAR_PTR
	bne .stateFail
	lda parameterStorageOffsetLo+10
	cmp #$16
	bne .stateFail
	lda persistentParamStart+IDX_MAIN
	cmp #11
	bne .stateFail
	lda persistentParamCount+IDX_MAIN
	bne .stateFail

	;; Only explicit static initializers emitted bytes. Uninitialized BSS did not.
	lda emittedByteCount
	cmp #20
	bne .dataFail
	ldx #$00
.dataLoop:
	lda emittedBytes,x
	cmp expectedData,x
	bne .dataFail
	inx
	cpx #expectedDataEnd-expectedData
	bne .dataLoop
	sec
	rts
.stateFail:
	lda #FAIL_VALID_STATE
	clc
	rts
.dataFail:
	lda #FAIL_VALID_DATA
	clc
	rts

;;; A unit with only one uninitialized array before main emits no data payload.
test_bss_only:
	jsr set_default_bss
	lda #bssNameEnd-bssName
	ldx #<bssName
	ldy #>bssName
	jsr parse_fixture
	bcc .fail
	lda emittedByteCount
	bne .fail
	lda zeroRequiredEnd
	cmp #4
	bne .fail
	lda bssOffset
	cmp #4
	bne .fail
	sec
	rts
.fail:
	lda fixtureOpenFailed
	beq .normal
	lda #FAIL_OPEN
	clc
	rts
.normal:
	lda #FAIL_BSS_ONLY
	clc
	rts

;;; Pending local name is invisible inside its own initializer, so `value + 1`
;;; resolves the global. After the declaration, `return value` resolves local.
test_shadowing:
	jsr set_default_bss
	lda #shadowNameEnd-shadowName
	ldx #<shadowName
	ldy #>shadowName
	jsr parse_fixture
	bcc .fail
	sec
	rts
.fail:
	lda fixtureOpenFailed
	beq .normal
	lda #FAIL_OPEN
	clc
	rts
.normal:
	lda #FAIL_SHADOW
	clc
	rts

;;; Error cases remain deliberately named rather than table-driven so a reader
;;; can see exactly which source rule each native fixture exercises.
test_duplicate_global:
	lda #PARSE_DUPLICATE_SYMBOL
	sta expectedParserError
	jsr set_default_bss
	lda #dupGlobalNameEnd-dupGlobalName
	ldx #<dupGlobalName
	ldy #>dupGlobalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_DUP_GLOBAL
	clc
	rts
.ok:
	sec
	rts

test_duplicate_function:
	lda #PARSE_DUPLICATE_SYMBOL
	sta expectedParserError
	jsr set_default_bss
	lda #dupFunctionNameEnd-dupFunctionName
	ldx #<dupFunctionName
	ldy #>dupFunctionName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_DUP_FUNCTION
	clc
	rts
.ok:
	sec
	rts

test_duplicate_parameter:
	lda #PARSE_DUPLICATE_SYMBOL
	sta expectedParserError
	jsr set_default_bss
	lda #dupParameterNameEnd-dupParameterName
	ldx #<dupParameterName
	ldy #>dupParameterName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_DUP_PARAMETER
	clc
	rts
.ok:
	sec
	rts

test_duplicate_local:
	lda #PARSE_DUPLICATE_SYMBOL
	sta expectedParserError
	jsr set_default_bss
	lda #dupLocalNameEnd-dupLocalName
	ldx #<dupLocalName
	ldy #>dupLocalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_DUP_LOCAL
	clc
	rts
.ok:
	sec
	rts

test_late_global:
	lda #PARSE_GLOBAL_AFTER_FUNCTION
	sta expectedParserError
	jsr set_default_bss
	lda #lateGlobalNameEnd-lateGlobalName
	ldx #<lateGlobalName
	ldy #>lateGlobalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_LATE_GLOBAL
	clc
	rts
.ok:
	sec
	rts

test_late_local:
	lda #PARSE_LATE_LOCAL
	sta expectedParserError
	jsr set_default_bss
	lda #lateLocalNameEnd-lateLocalName
	ldx #<lateLocalName
	ldy #>lateLocalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_LATE_LOCAL
	clc
	rts
.ok:
	sec
	rts

test_self_local:
	lda #PARSE_UNDECLARED
	sta expectedParserError
	jsr set_default_bss
	lda #selfLocalNameEnd-selfLocalName
	ldx #<selfLocalName
	ldy #>selfLocalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_SELF_LOCAL
	clc
	rts
.ok:
	sec
	rts

test_forward_local:
	lda #PARSE_UNDECLARED
	sta expectedParserError
	jsr set_default_bss
	lda #forwardLocalNameEnd-forwardLocalName
	ldx #<forwardLocalName
	ldy #>forwardLocalName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_FORWARD_LOCAL
	clc
	rts
.ok:
	sec
	rts

test_later_function:
	lda #PARSE_UNDECLARED
	sta expectedParserError
	jsr set_default_bss
	lda #laterFunctionNameEnd-laterFunctionName
	ldx #<laterFunctionName
	ldy #>laterFunctionName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_LATER_FUNCTION
	clc
	rts
.ok:
	sec
	rts

test_too_many_initializers:
	lda #PARSE_TOO_MANY_INITIALIZERS
	sta expectedParserError
	jsr set_default_bss
	lda #tooManyNameEnd-tooManyName
	ldx #<tooManyName
	ldy #>tooManyName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_TOO_MANY
	clc
	rts
.ok:
	sec
	rts

test_string_fit:
	lda #PARSE_STRING_TOO_LONG
	sta expectedParserError
	jsr set_default_bss
	lda #stringFitNameEnd-stringFitName
	ldx #<stringFitName
	ldy #>stringFitName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_STRING_FIT
	clc
	rts
.ok:
	sec
	rts

test_bss_overflow:
	lda #PARSE_BSS_OVERFLOW
	sta expectedParserError
	lda #$fd
	sta bssBase
	lda #$ff
	sta bssBase+1
	lda #bssNameEnd-bssName
	ldx #<bssName
	ldy #>bssName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_BSS_OVERFLOW
	clc
	rts
.ok:
	sec
	rts

test_char_range:
	lda #PARSE_VALUE_RANGE
	sta expectedParserError
	jsr set_default_bss
	lda #charRangeNameEnd-charRangeName
	ldx #<charRangeName
	ldy #>charRangeName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_CHAR_RANGE
	clc
	rts
.ok:
	sec
	rts

test_int_range:
	lda #PARSE_VALUE_RANGE
	sta expectedParserError
	jsr set_default_bss
	lda #intRangeNameEnd-intRangeName
	ldx #<intRangeName
	ldy #>intRangeName
	jsr expect_fixture_error
	bcs .ok
	lda #FAIL_INT_RANGE
	clc
	rts
.ok:
	sec
	rts

set_default_bss:
	lda #$00
	sta bssBase
	lda #$50
	sta bssBase+1
	rts

;;; A=filename length, X/Y=filename address.
parse_fixture:
	sta sourceNameLength
	stx sourceName
	sty sourceName+1
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	lda #$00
	sta fixtureOpenFailed
	jsr reset_emitter
	jsr open_source
	bcs .opened
	lda #$01
	sta fixtureOpenFailed
	clc
	rts
.opened:
	jsr parse_translation_unit
	rts

;;; A=length, X/Y=name, expectedParserError already set.
expect_fixture_error:
	jsr parse_fixture
	bcs .wrong
	lda fixtureOpenFailed
	bne .wrong
	lda parserError
	cmp expectedParserError
	bne .wrong
	sec
	rts
.wrong:
	clc
	rts

;;; Streaming emitter test double. Production declarations never retain these
;;; bytes; this small buffer exists only for native inspection.
reset_emitter:
	lda #$00
	sta emittedByteCount
	sta emittedPersistentCount
	sta emittedCurrentCount
	sta emittedBoundaryCount
	rts

emit_persistent_symbol:
	inc emittedPersistentCount
	sec
	rts

emit_current_symbol:
	inc emittedCurrentCount
	sec
	rts

emit_static_byte:
	ldx emittedByteCount
	cpx #64
	bcs .full
	sta emittedBytes,x
	inc emittedByteCount
	sec
	rts
.full:
	clc
	rts

emit_bss_boundaries:
	inc emittedBoundaryCount
	sec
	rts

expectedData:
	byte 'A'
	byte $ff,$ff
	byte $00,$c0
	byte 0,1,0,0
	byte $00,$40,$00,$c0,$ff,$ff
	byte 'a','b','c',0,0
expectedDataEnd:

declsName:	byte 'D','E','C','L','S','.','C'
declsNameEnd:
bssName:	byte 'B','S','S','.','C'
bssNameEnd:
dupGlobalName:	byte 'D','U','P','G','L','O','B','A','L','.','C'
dupGlobalNameEnd:
dupFunctionName:	byte 'D','U','P','F','U','N','C','.','C'
dupFunctionNameEnd:
dupParameterName:	byte 'D','U','P','P','A','R','A','M','.','C'
dupParameterNameEnd:
dupLocalName:	byte 'D','U','P','L','O','C','A','L','.','C'
dupLocalNameEnd:
lateGlobalName:	byte 'L','A','T','E','G','L','O','B','A','L','.','C'
lateGlobalNameEnd:
lateLocalName:	byte 'L','A','T','E','L','O','C','A','L','.','C'
lateLocalNameEnd:
selfLocalName:	byte 'S','E','L','F','L','O','C','A','L','.','C'
selfLocalNameEnd:
forwardLocalName:	byte 'F','O','R','W','A','R','D','L','O','C','A','L','.','C'
forwardLocalNameEnd:
laterFunctionName:	byte 'L','A','T','E','R','F','U','N','C','.','C'
laterFunctionNameEnd:
shadowName:	byte 'S','H','A','D','O','W','.','C'
shadowNameEnd:
tooManyName:	byte 'T','O','O','M','A','N','Y','.','C'
tooManyNameEnd:
stringFitName:	byte 'S','T','R','I','N','G','F','I','T','.','C'
stringFitNameEnd:
charRangeName:	byte 'C','H','A','R','R','A','N','G','E','.','C'
charRangeNameEnd:
intRangeName:	byte 'I','N','T','R','A','N','G','E','.','C'
intRangeNameEnd:

expectedParserError:	byte 0
fixtureOpenFailed:	byte 0
emittedByteCount:	byte 0
emittedPersistentCount:	byte 0
emittedCurrentCount:	byte 0
emittedBoundaryCount:	byte 0
emittedBytes:		ds 64

	include "declarations.asm"
