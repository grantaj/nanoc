	include "../test.inc"

XT_OUTPUT_LFN = 3
XT_OUTPUT_DEVICE = 9

XT_FAIL_DEPTH  = $01
XT_FAIL_STRING = $02
XT_FAIL_OPEN   = $03
XT_FAIL_OUTPUT = $05

XT_EXPECTED_COUNT = 30

	* = $4000

main:
	jsr xt_test_depth_limit
	bcs .string
	jmp xt_finish
.string:
	jsr xt_test_string_pool
	bcs .runtime
	jmp xt_finish
.runtime:
	jsr xt_compile_runtime_fixture
	bcs .pass
	jmp xt_finish
.pass:
	lda #TEST_PASS
xt_finish:
	sta TEST_RESULT
.halt:
	jmp .halt

;;; The depth fixture proves the bounded operator stack fails cleanly rather
;;; than recursing or spilling C values onto the 6502 hardware stack.
xt_test_depth_limit:
	jsr xt_reset_hooks
	lda #depthNameEnd-depthName
	ldx #<depthName
	ldy #>depthName
	jsr xt_parse_fixture
	bcs .fail
	lda parserError
	cmp #PARSE_EXPRESSION_ERROR
	bne .fail
	lda expressionError
	cmp #EXPR_STACK_OVERFLOW
	bne .fail
	sec
	rts
.fail:
	lda #XT_FAIL_DEPTH
	clc
	rts

;;; String literals are retained only as a generated identity plus deferred
;;; bytes. Emission is disabled here: inspect the narrow pool after the complete
;;; translation unit has been parsed.
xt_test_string_pool:
	jsr xt_reset_hooks
	lda #stringNameEnd-stringName
	ldx #<stringName
	ldy #>stringName
	jsr xt_parse_fixture
	bcc .fail
	lda literalCount
	cmp #1
	bne .fail
	lda literalLength
	cmp #5
	bne .fail
	lda literalLength+1
	bne .fail
	ldx #$00
.loop:
	lda literalBytes,x
	cmp xtExpectedString,x
	bne .fail
	inx
	cpx #xtExpectedStringEnd-xtExpectedString
	bne .loop
	sec
	rts
.fail:
	lda #XT_FAIL_STRING
	clc
	rts

;;; Compile a real Phase 1 source file to ordinary ass source. This test image
;;; contains no second evaluator: the semantic oracle is the fixed result table
;;; used by the separately assembled/executed generated program.
xt_compile_runtime_fixture:
	jsr xt_reset_hooks
	lda #$01
	sta xtRuntimeMode

	lda #runtimeNameEnd-runtimeName
	ldx #<runtimeName
	ldy #>runtimeName
	jsr xt_set_source
	jsr open_source
	bcc .openFail
	jsr xt_open_output
	bcc .outputFail
	jsr xt_emit_header
	bcc .outputFail
	jsr parse_translation_unit
	bcc .compileFail
	jsr xt_close_output
	sec
	rts

.openFail:
	lda #XT_FAIL_OPEN
	clc
	rts
.compileFail:
	;;; Preserve the compiler's layered diagnostic in the normal one-byte native
	;;; test result. $20.. reports scannerError; $40.. reports parserError;
	;;; $80.. reports expressionError at the declaration/expression boundary.
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
	pha
	jsr xt_close_output
	pla
	clc
	rts
.outputFail:
	jsr close_source
	jsr xt_close_output
	lda #XT_FAIL_OUTPUT
	clc
	rts

;;; A=filename length, X/Y=filename address. Output stays disabled.
xt_parse_fixture:
	jsr xt_set_source
	jsr open_source
	bcc .failed
	jsr parse_translation_unit
	php
	jsr close_source
	plp
	rts
.failed:
	clc
	rts

xt_set_source:
	sta sourceNameLength
	stx sourceName
	sty sourceName+1
	lda #$08
	sta sourceDevice
	lda #SOURCE_LFN_DEFAULT
	sta sourceLfn
	rts

xt_reset_hooks:
	lda #$00
	sta emitOutputEnabled
	sta xtRuntimeMode
	sta xtStarted
	sta xtDataColumn
	sta xtDataRemaining
	sta xtDataRemaining+1
	sta xtCheckIndex
	sta xtOutputOpen
	lda #$ff
	sta xtFunctionIndex
	rts

;;; ---------------------------------------------------------------------------
;;; Output file
;;; ---------------------------------------------------------------------------

;;; Open the drive-9 logical file but do not CHKOUT it here. The production
;;; byte emitter owns IEC TALK/LISTEN selection, exactly as it does in nanoc0.
xt_open_output:
	lda #outputNameEnd-outputName
	ldx #<outputName
	ldy #>outputName
	jsr SETNAM
	lda #XT_OUTPUT_LFN
	ldx #XT_OUTPUT_DEVICE
	ldy #XT_OUTPUT_LFN
	jsr SETLFS
	jsr OPEN
	bcs .failed
	lda #$01
	sta xtOutputOpen
	sta emitOutputEnabled
	sec
	rts
.failed:
	clc
	rts

xt_close_output:
	lda #$00
	sta emitOutputEnabled
	jsr CLRCHN
	lda #COMPILER_IO_NONE
	sta compilerIecDirection
	lda xtOutputOpen
	beq .done
	lda #XT_OUTPUT_LFN
	jsr CLOSE
	lda #$00
	sta xtOutputOpen
.done:
	rts

xt_emit_header:
	lda #xtHeaderEnd-xtHeader
	ldx #<xtHeader
	ldy #>xtHeader
	jmp emit_text

;;; ---------------------------------------------------------------------------
;;; Declaration emission hooks
;;; ---------------------------------------------------------------------------

;;; A=EMIT_STORAGE_*, X=persistent symbol index.
emit_persistent_symbol:
	sta xtStorageKind
	stx xtSavedSymbol
	lda xtRuntimeMode
	bne .runtime
	sec
	rts
.runtime:
	lda xtStorageKind
	cmp #EMIT_STORAGE_BSS
	beq .bss
	cmp #EMIT_STORAGE_DATA
	beq .data

	;;; The only NONE persistent object in this fixture is main. Remember its
	;;; identity so the post-function checker can regenerate local slot names.
	ldx xtSavedSymbol
	lda persistentKind,x
	cmp #SYMBOL_FUNCTION
	bne .done
	stx xtFunctionIndex
.done:
	sec
	rts

.bss:
	ldx xtSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	jsr xt_emit_bss_assignment
	rts

.data:
	ldx xtSavedSymbol
	jsr emit_persistent_name
	bcc .failed
	lda #':'
	jsr emit_output_byte
	bcc .failed
	jsr emit_newline
	bcc .failed
	jsr xt_set_data_size
	lda #$00
	sta xtDataColumn
	sec
	rts
.failed:
	clc
	rts

;;; X=current-function symbol index. allocOffset is the slot just allocated.
emit_current_symbol:
	stx xtSavedSymbol
	lda xtRuntimeMode
	bne .runtime
	sec
	rts
.runtime:
	ldx xtSavedSymbol
	jsr emit_current_name
	bcc .failed
	jsr xt_emit_bss_assignment
	bcc .failed
	lda xtStarted
	bne .done
	lda #$01
	sta xtStarted
	lda #xtStartEnd-xtStart
	ldx #<xtStart
	ldy #>xtStart
	jsr emit_text
.done:
	rts
.failed:
	clc
	rts

;;; A=one initialized global-data byte. Break rows at 16 bytes so the generated
;;; assembler source stays comfortably inside ass's line buffer.
emit_static_byte:
	sta xtStaticByte
	lda xtRuntimeMode
	bne .runtime
	sec
	rts
.runtime:
	lda xtDataColumn
	bne .comma
	lda #xtBytePrefixEnd-xtBytePrefix
	ldx #<xtBytePrefix
	ldy #>xtBytePrefix
	jsr emit_text
	bcc .failed
	jmp .byte
.comma:
	lda #','
	jsr emit_output_byte
	bcc .failed
.byte:
	lda #'$'
	jsr emit_output_byte
	bcc .failed
	lda xtStaticByte
	jsr emit_hex_byte
	bcc .failed
	jsr xt_decrement_data_remaining
	inc xtDataColumn
	lda xtDataRemaining
	ora xtDataRemaining+1
	beq .newline
	lda xtDataColumn
	cmp #16
	bne .done
.newline:
	jsr emit_newline
	bcc .failed
	lda #$00
	sta xtDataColumn
.done:
	sec
	rts
.failed:
	clc
	rts

;;; Source EOF leaves no IEC stream selected. The production emitter notices
;;; that state and selects the still-open drive-9 output file on the first byte.
emit_bss_boundaries:
	lda xtRuntimeMode
	bne .runtime
	sec
	rts
.runtime:
	jsr xt_emit_bss_end
	bcc .failed
	;;; The checker is test scaffolding, not part of the C function. Give it a
	;;; global anchor so its sixty short branch labels have their own assembler
	;;; local-label lifetime instead of inflating the function's local arena.
	lda #xtCheckerScopeEnd-xtCheckerScope
	ldx #<xtCheckerScope
	ldy #>xtCheckerScope
	jsr emit_text
	bcc .failed
	jsr xt_emit_checker
	bcc .failed
	jsr emit_runtime_helpers
	bcc .failed
	sec
	rts
.failed:
	clc
	rts

;;; Kept as test source history for now; the fixture above deliberately uses
;;; production emit_runtime_helpers instead of this private copy.
xt_emit_mul16:
	lda #xtMul16Part2-xtMul16
	ldx #<xtMul16
	ldy #>xtMul16
	jsr emit_text
	bcs .part2
	rts
.part2:
	lda #xtMul16End-xtMul16Part2
	ldx #<xtMul16Part2
	ldy #>xtMul16Part2
	jmp emit_text

xt_emit_bss_assignment:
	lda #xtBssAssignEnd-xtBssAssign
	ldx #<xtBssAssign
	ldy #>xtBssAssign
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

xt_emit_bss_end:
	lda #xtBssEndPrefixEnd-xtBssEndPrefix
	ldx #<xtBssEndPrefix
	ldy #>xtBssEndPrefix
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

xt_set_data_size:
	ldx xtSavedSymbol
	lda persistentKind,x
	cmp #SYMBOL_ARRAY
	beq .array
	lda persistentType,x
	cmp #TYPE_CHAR
	beq .one
	lda #$02
	sta xtDataRemaining
	lda #$00
	sta xtDataRemaining+1
	rts
.one:
	lda #$01
	sta xtDataRemaining
	lda #$00
	sta xtDataRemaining+1
	rts
.array:
	lda arrayLength
	sta xtDataRemaining
	lda arrayLength+1
	sta xtDataRemaining+1
	lda persistentType,x
	cmp #TYPE_CHAR
	beq .done
	asl xtDataRemaining
	rol xtDataRemaining+1
.done:
	rts

xt_decrement_data_remaining:
	lda xtDataRemaining
	bne .low
	dec xtDataRemaining+1
.low:
	dec xtDataRemaining
	rts

;;; ---------------------------------------------------------------------------
;;; Generated result checker
;;; ---------------------------------------------------------------------------

;;; Every runtime-fixture local is a two-byte scalar. The expected table below
;;; is deliberately just constants. The generated program compares its actual
;;; static slots against them and returns TEST_PASS or the 1-based local index.
xt_emit_checker:
	lda xtFunctionIndex
	cmp #$ff
	bne .haveFunction
	clc
	rts
.haveFunction:
	sta currentFunctionIndex
	lda #$00
	sta xtCheckIndex
.loop:
	jsr xt_emit_check_low
	bcc .failed
	jsr xt_emit_check_high
	bcc .failed
	inc xtCheckIndex
	lda xtCheckIndex
	cmp #XT_EXPECTED_COUNT
	bne .loop
	lda #xtPassEnd-xtPass
	ldx #<xtPass
	ldy #>xtPass
	jmp emit_text
.failed:
	clc
	rts

xt_emit_check_low:
	lda #$00
	sta xtCheckHigh
	lda xtCheckIndex
	asl
	tay
	lda xtExpectedValues,y
	sta xtExpectedByte
	jmp xt_emit_check_byte

xt_emit_check_high:
	lda #$01
	sta xtCheckHigh
	lda xtCheckIndex
	asl
	tay
	iny
	lda xtExpectedValues,y
	sta xtExpectedByte

;;; Failure from any formatter below can return immediately: carry is already
;;; clear. That avoids one distant shared failure branch in this deliberately
;;; repetitive checker generator.
xt_emit_check_byte:
	lda #xtLdaPrefixEnd-xtLdaPrefix
	ldx #<xtLdaPrefix
	ldy #>xtLdaPrefix
	jsr emit_text
	bcs .loadName
	rts
.loadName:
	ldx xtCheckIndex
	jsr emit_current_name
	bcs .loadHigh
	rts
.loadHigh:
	lda xtCheckHigh
	beq .loadDone
	lda #exprPlusOneEnd-exprPlusOne
	ldx #<exprPlusOne
	ldy #>exprPlusOne
	jsr emit_text
	bcs .loadDone
	rts
.loadDone:
	jsr emit_newline
	bcs .compare
	rts

.compare:
	lda #xtCmpPrefixEnd-xtCmpPrefix
	ldx #<xtCmpPrefix
	ldy #>xtCmpPrefix
	jsr emit_text
	bcs .expected
	rts
.expected:
	lda xtExpectedByte
	jsr emit_hex_byte
	bcs .compareDone
	rts
.compareDone:
	jsr emit_newline
	bcs .reserve
	rts

.reserve:
	jsr reserve_generated_label
	lda emitLabelValue
	sta xtCheckLabel
	lda emitLabelValue+1
	sta xtCheckLabel+1
	lda #xtBeqPrefixEnd-xtBeqPrefix
	ldx #<xtBeqPrefix
	ldy #>xtBeqPrefix
	jsr emit_text
	bcs .branchName
	rts
.branchName:
	lda xtCheckLabel
	sta emitLabelValue
	lda xtCheckLabel+1
	sta emitLabelValue+1
	jsr emit_generated_label_name
	bcs .branchDone
	rts
.branchDone:
	jsr emit_newline
	bcs .failureValue
	rts

.failureValue:
	lda #xtFailPrefixEnd-xtFailPrefix
	ldx #<xtFailPrefix
	ldy #>xtFailPrefix
	jsr emit_text
	bcs .failureCode
	rts
.failureCode:
	lda xtCheckIndex
	clc
	adc #$01
	jsr emit_hex_byte
	bcs .failureLine
	rts
.failureLine:
	jsr emit_newline
	bcs .failureReturn
	rts
.failureReturn:
	lda #xtRtsEnd-xtRts
	ldx #<xtRts
	ldy #>xtRts
	jsr emit_text
	bcs .successLabel
	rts

.successLabel:
	lda xtCheckLabel
	sta emitLabelValue
	lda xtCheckLabel+1
	sta emitLabelValue+1
	jmp emit_label_definition

;;; ---------------------------------------------------------------------------
;;; Fixed test-output fragments
;;; ---------------------------------------------------------------------------

xtHeader:
	byte '*',' ','=',' ','$','0','8','0','0',$0a
	byte 'N','C','_','T','M','P',' ','=',' ','$','f','c',$0a
	byte 'N','C','_','P','T','R',' ','=',' ','$','f','e',$0a
	byte 'N','C','_','B','S','S',' ','=',' ','$','3','8','0','0',$0a
	byte $09,'j','m','p',' ','_','_','t','e','s','t','_','s','t','a','r','t',$0a
xtHeaderEnd:

xtStart:
	byte '_','_','t','e','s','t','_','s','t','a','r','t',':',$0a
	byte $09,'c','l','d',$0a
xtStartEnd:

;;; This global label is intentionally emitted between the compiled function and
;;; the test-only checker. It has no runtime cost; it only starts a fresh `ass`
;;; local-label lifetime for the checker's generated `.LNN` branches.
xtCheckerScope:	byte '_','_','t','e','s','t','_','c','h','e','c','k',':',$0a
xtCheckerScopeEnd:

xtBytePrefix:	byte $09,'b','y','t','e',' '
xtBytePrefixEnd:
xtBssAssign:	byte ' ','=',' ','N','C','_','B','S','S','+','$'
xtBssAssignEnd:
xtBssEndPrefix:	byte '_','_','n','c','_','b','s','s','_','e','n','d',' ','=',' ','N','C','_','B','S','S','+','$'
xtBssEndPrefixEnd:
xtLdaPrefix:	byte $09,'l','d','a',' '
xtLdaPrefixEnd:
xtCmpPrefix:	byte $09,'c','m','p',' ','#','$'
xtCmpPrefixEnd:
xtBeqPrefix:	byte $09,'b','e','q',' '
xtBeqPrefixEnd:
xtFailPrefix:	byte $09,'l','d','a',' ','#','$'
xtFailPrefixEnd:
xtRts:		byte $09,'r','t','s',$0a
xtRtsEnd:
xtPass:
	byte $09,'l','d','a',' ','#','$','f','f',$0a
	byte $09,'r','t','s',$0a
xtPassEnd:

;;; Small obvious 16-bit shift/add multiply helper. Left arrives in NC_TMP,
;;; right in A/X, and the low 16-bit result returns in A/X. Y/X accumulate the
;;; result; NC_PTR holds and shifts the multiplier. No C value uses page $0100.
xtMul16:
	byte '_','_','n','c','_','m','u','l','1','6',':',$0a
	byte $09,'s','t','a',' ','N','C','_','P','T','R',$0a
	byte $09,'s','t','x',' ','N','C','_','P','T','R','+','1',$0a
	byte $09,'l','d','y',' ','#','$','0','0',$0a
	byte $09,'l','d','x',' ','#','$','0','0',$0a
	byte '_','_','n','c','_','m','u','l','1','6','_','l','o','o','p',':',$0a
	byte $09,'l','d','a',' ','N','C','_','P','T','R',$0a
	byte $09,'o','r','a',' ','N','C','_','P','T','R','+','1',$0a
	byte $09,'b','e','q',' ','_','_','n','c','_','m','u','l','1','6','_','d','o','n','e',$0a
	byte $09,'l','d','a',' ','N','C','_','P','T','R',$0a
	byte $09,'a','n','d',' ','#','$','0','1',$0a
	byte $09,'b','e','q',' ','_','_','n','c','_','m','u','l','1','6','_','n','o','a','d','d',$0a
xtMul16Part2:
	byte $09,'t','y','a',$0a
	byte $09,'c','l','c',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P',$0a
	byte $09,'t','a','y',$0a
	byte $09,'t','x','a',$0a
	byte $09,'a','d','c',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'t','a','x',$0a
	byte '_','_','n','c','_','_','m','u','l','1','6','_','n','o','a','d','d',':',$0a
	byte $09,'a','s','l',' ','N','C','_','T','M','P',$0a
	byte $09,'r','o','l',' ','N','C','_','T','M','P','+','1',$0a
	byte $09,'l','s','r',' ','N','C','_','P','T','R','+','1',$0a
	byte $09,'r','o','r',' ','N','C','_','P','T','R',$0a
	byte $09,'j','m','p',' ','_','_','n','c','_','m','u','l','1','6','_','l','o','o','p',$0a
	byte '_','_','n','c','_','m','u','l','1','6','_','d','o','n','e',':',$0a
	byte $09,'t','y','a',$0a
	byte $09,'c','l','d',$0a
	byte $09,'r','t','s',$0a
xtMul16End:

;;; Expected A/X results of the 30 locals in expressions.c, low byte first.
xtExpectedValues:
	word $0000,$7fff,$8000,$ffff,$00ff,$0001,$ffff,$000e
	word $0014,$0018,$0008,$0001,$100f,$fffd,$0001,$8000
	word $0001,$0001,$0000,$0000,$0001,$0001,$0001,$0001
	word $fffe,$0001,$0065,$1234,$0001,$0000

xtExpectedString:	byte 'h','e','l','l','o',0
xtExpectedStringEnd:

depthName:	byte 'D','E','P','T','H','.','C'
depthNameEnd:
stringName:	byte 'S','T','R','I','N','G','.','C'
stringNameEnd:
runtimeName:	byte 'E','X','P','R','E','S','S','I','O','N','S','.','C'
runtimeNameEnd:
outputName:	byte 'E','X','P','R','O','U','T','.','A','S','M',',','S',',','W'
outputNameEnd:

xtRuntimeMode:		byte 0
xtStarted:		byte 0
xtStorageKind:		byte 0
xtSavedSymbol:		byte 0
xtFunctionIndex:	byte $ff
xtStaticByte:		byte 0
xtDataRemaining:	word 0
xtDataColumn:		byte 0
xtCheckIndex:		byte 0
xtCheckHigh:		byte 0
xtExpectedByte:		byte 0
xtCheckLabel:		word 0
xtOutputOpen:		byte 0

	include "declarations.asm"
	include "runtime_codegen.asm"