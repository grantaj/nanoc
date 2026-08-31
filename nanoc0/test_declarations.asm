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
IDX_SOURCE    = 8
IDX_C         = 9
IDX_BYTES     = 12
IDX_WIDTHS    = 15
IDX_HELPER    = 18
IDX_MAIN      = 19

;;; Declarations plus scanner/symbol state are exercised as one native image.
;;; Storage offsets are inspected when the emitter receives them, not retained
;;; in symbol tables merely so a test can look at them later. This mirrors the
;;; production contract: emit the assembler-visible identity, then forget the
;;; numeric address and BSS/data placement.
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

;;; Comprehensive valid translation. Keep each representation invariant in a
;;; small named check so the test doubles as a readable map of #54's state.
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
	jsr check_valid_counts
	bcc .stateFail
	jsr check_valid_bss_layout
	bcc .stateFail
	jsr check_valid_current_layout
	bcc .stateFail
	jsr check_valid_symbol_kinds
	bcc .stateFail
	jsr check_valid_function_metadata
	bcc .stateFail
	jsr check_valid_data
	bcc .dataFail
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

check_valid_counts:
	lda parserError
	bne .no
	lda persistentCount
	cmp #20
	bne .no
	lda userFunctionCount
	cmp #2
	bne .no
	lda currentCount
	bne .no
	lda bssOffset
	cmp #$24
	bne .no
	lda bssOffset+1
	bne .no
	lda zeroRequiredEnd
	cmp #$13
	bne .no
	lda zeroRequiredEnd+1
	bne .no
	lda emittedPersistentCount
	cmp #15
	bne .no
	lda emittedCurrentCount
	cmp #9
	bne .no
	lda emittedBoundaryCount
	cmp #1
	bne .no
	lda persistentKind
	cmp #SYMBOL_RUNTIME_FUNCTION
	bne .no
	lda persistentParamCount
	cmp #2
	bne .no
	lda persistentParamCount+3
	cmp #2
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; Exact uninitialized-global NC_BSS layout is observed at emission time.
;;; char=1; every 16-bit scalar/element form=2.
check_valid_bss_layout:
	lda emittedOffsetHighNonzero
	bne .no
	lda emittedBssCount
	cmp #expectedBssOffsetsEnd-expectedBssOffsets
	bne .no
	ldx #$00
.loop:
	lda emittedBssOffsets,x
	cmp expectedBssOffsets,x
	bne .no
	inx
	cpx #expectedBssOffsetsEnd-expectedBssOffsets
	bne .loop
	lda persistentType+IDX_FLAG
	cmp #TYPE_CHAR
	bne .no
	lda persistentType+IDX_SOURCE
	cmp #TYPE_CHAR_PTR
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; Parameters/locals are likewise emitted with their just-allocated offset and
;;; then represented only by name/type. The current table itself is reusable.
check_valid_current_layout:
	lda emittedCurrentOffsetCount
	cmp #expectedCurrentOffsetsEnd-expectedCurrentOffsets
	bne .no
	ldx #$00
.loop:
	lda emittedCurrentOffsets,x
	cmp expectedCurrentOffsets,x
	bne .no
	inx
	cpx #expectedCurrentOffsetsEnd-expectedCurrentOffsets
	bne .loop
	sec
	rts
.no:
	clc
	rts

;;; Persistent kind records source meaning, not where storage happened to be
;;; emitted. Initialized and uninitialized globals therefore have the same kind;
;;; initialized and uninitialized arrays likewise share one array kind.
check_valid_symbol_kinds:
	lda persistentKind+IDX_FLAG
	cmp #SYMBOL_GLOBAL
	bne .no
	lda persistentKind+IDX_C
	cmp #SYMBOL_GLOBAL
	bne .no
	lda persistentKind+IDX_BYTES
	cmp #SYMBOL_ARRAY
	bne .no
	lda persistentKind+IDX_WIDTHS
	cmp #SYMBOL_ARRAY
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; helper(char p,unsigned q,char *s) retains only caller-relevant metadata:
;;; parameter start/count and types. Numeric slot addresses are deliberately not
;;; present; later calls regenerate the parameter labels from function+ordinal.
check_valid_function_metadata:
	lda persistentKind+IDX_HELPER
	cmp #SYMBOL_FUNCTION
	bne .no
	lda persistentParamStart+IDX_HELPER
	cmp #8
	bne .no
	lda persistentParamCount+IDX_HELPER
	cmp #3
	bne .no
	lda parameterType+8
	cmp #TYPE_CHAR
	bne .no
	lda parameterType+9
	cmp #TYPE_UNSIGNED
	bne .no
	lda parameterType+10
	cmp #TYPE_CHAR_PTR
	bne .no
	lda persistentParamStart+IDX_MAIN
	cmp #11
	bne .no
	lda persistentParamCount+IDX_MAIN
	bne .no
	sec
	rts
.no:
	clc
	rts

;;; Only explicit static initializers emit payload bytes.
check_valid_data:
	lda emittedByteCount
	cmp #expectedDataEnd-expectedData
	bne .no
	ldx #$00
.loop:
	lda emittedBytes,x
	cmp expectedData,x
	bne .no
	inx
	cpx #expectedDataEnd-expectedData
	bne .loop
	sec
	rts
.no:
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

;;; The not-yet-visible local slot does not participate in lookup inside its own
;;; initializer, so `value + 1` resolves the global. After visibility advances,
;;; `return value` resolves the local.
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

;;; Error cases stay named rather than table-driven so the source rule under
;;; test is visible without decoding a compact test-data format.
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

;;; #55 gives expression failures their own diagnostic layer. The declaration
;;; parser says "initializer expression failed" while expressionError preserves
;;; the precise undeclared-name cause. Assert both rather than flattening the
;;; expression engine back into #54's temporary declaration-only scanner.
test_self_local:
	lda #PARSE_EXPRESSION_ERROR
	sta expectedParserError
	jsr set_default_bss
	lda #selfLocalNameEnd-selfLocalName
	ldx #<selfLocalName
	ldy #>selfLocalName
	jsr expect_fixture_error
	bcc .fail
	lda expressionError
	cmp #EXPR_UNDECLARED
	beq .ok
.fail:
	lda #FAIL_SELF_LOCAL
	clc
	rts
.ok:
	sec
	rts

test_forward_local:
	lda #PARSE_EXPRESSION_ERROR
	sta expectedParserError
	jsr set_default_bss
	lda #forwardLocalNameEnd-forwardLocalName
	ldx #<forwardLocalName
	ldy #>forwardLocalName
	jsr expect_fixture_error
	bcc .fail
	lda expressionError
	cmp #EXPR_UNDECLARED
	beq .ok
.fail:
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
;;; bytes/offsets; the buffers exist only so the native test can inspect what was
;;; presented at the emission boundary.
reset_emitter:
	lda #$00
	sta emittedByteCount
	sta emittedPersistentCount
	sta emittedCurrentCount
	sta emittedBoundaryCount
	sta emittedBssCount
	sta emittedCurrentOffsetCount
	sta emittedOffsetHighNonzero
	rts

;;; A says where this declaration is being emitted right now. persistentKind
;;; deliberately does not retain that historical placement.
emit_persistent_symbol:
	inc emittedPersistentCount
	cmp #EMIT_STORAGE_BSS
	bne .done
	ldy emittedBssCount
	cpy #16
	bcs .done
	lda allocOffset
	sta emittedBssOffsets,y
	lda allocOffset+1
	beq .lowOnly
	lda #$01
	sta emittedOffsetHighNonzero
.lowOnly:
	inc emittedBssCount
.done:
	sec
	rts

emit_current_symbol:
	inc emittedCurrentCount
	ldy emittedCurrentOffsetCount
	cpy #16
	bcs .done
	lda allocOffset
	sta emittedCurrentOffsets,y
	lda allocOffset+1
	beq .lowOnly
	lda #$01
	sta emittedOffsetHighNonzero
.lowOnly:
	inc emittedCurrentOffsetCount
.done:
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

expectedBssOffsets:
	byte 0,1,3,5,7,11,15
expectedBssOffsetsEnd:
expectedCurrentOffsets:
	byte 19,20,22,24,26,28,30,32,34
expectedCurrentOffsetsEnd:

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
emittedBssCount:	byte 0
emittedCurrentOffsetCount:	byte 0
emittedOffsetHighNonzero:	byte 0
emittedBssOffsets:	ds 16
emittedCurrentOffsets:	ds 16
emittedBytes:		ds 64

	include "declarations.asm"