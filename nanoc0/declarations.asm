;;; declarations.asm
;;;
;;; Nano C Phase 1 declaration parser.
;;;
;;; This is deliberately only the declaration/storage half of the parser.  It
;;; consumes the translation unit from top to bottom, emits static initializer
;;; bytes immediately, records symbols that later source may use, and skips the
;;; executable statement bodies that #55/#56 will compile.
;;;
;;; Four tiny output hooks are supplied by the eventual compiler driver and by
;;; the native tests in this issue:
;;;
;;;   emit_persistent_symbol   X = persistent symbol index
;;;   emit_current_symbol      X = current-function symbol index
;;;   emit_static_byte         A = one initialized-data byte
;;;   emit_bss_boundaries      reads zeroRequiredEnd/bssOffset
;;;
;;; Each hook returns carry set on success.  They exist so initialized global
;;; data can remain streaming: nanoc0 does not retain a second data image in RAM.
;;;
;;; Local initializers are intentionally not expression-parsed here.  Until #55
;;; lands, validate_local_initializer consumes the expression tokens and checks
;;; only declaration-before-use.  The new local stays invisible until that scan
;;; reaches ';'.  #55 replaces this single hook point with real expression code
;;; generation rather than inheriting a second expression implementation.

	include "scanner.asm"
	include "symbols.asm"

PARSE_OK                    = 0
PARSE_SCANNER_ERROR         = 1
PARSE_EXPECTED_TYPE         = 2
PARSE_EXPECTED_IDENTIFIER   = 3
PARSE_DUPLICATE_SYMBOL      = 4
PARSE_GLOBAL_AFTER_FUNCTION = 5
PARSE_BAD_DECLARATOR        = 6
PARSE_BAD_INITIALIZER       = 7
PARSE_BAD_ARRAY_SIZE        = 8
PARSE_TOO_MANY_INITIALIZERS = 9
PARSE_STRING_TOO_LONG       = 10
PARSE_BSS_OVERFLOW          = 11
PARSE_SYMBOL_CAPACITY       = 12
PARSE_PARAMETER_CAPACITY    = 13
PARSE_LATE_LOCAL            = 14
PARSE_UNDECLARED            = 15
PARSE_EMIT_ERROR            = 16
PARSE_BAD_FUNCTION          = 17
PARSE_UNTERMINATED_FUNCTION = 18
PARSE_BAD_CONSTANT          = 19
PARSE_VALUE_RANGE           = 20
PARSE_LOCAL_ARRAY           = 21
PARSE_EXPECTED_FUNCTION     = 22
PARSE_NAME_CAPACITY         = 23

;;; parse_translation_unit
;;; Source must already be open. bssBase must already contain the wrapper's
;;; chosen NC_BSS base. Carry set means a complete Phase 1 translation unit was
;;; consumed. Carry clear leaves parserError with the reason.
parse_translation_unit:
	lda #PARSE_OK
	sta parserError
	lda #$00
	sta translationInFunctions
	jsr reset_symbol_state
	jsr parser_next
	bcc .failed

.loop:
	lda currentTokenKind
	cmp #TOKEN_EOF
	beq .end
	jsr is_type_token
	bcc .expectedType
	jsr parse_top_level_declaration
	bcc .failed
	jmp .loop

.end:
	lda userFunctionCount
	beq .expectedFunction
	jsr emit_bss_boundaries
	bcc .emitFail
	sec
	rts
.expectedType:
	lda #PARSE_EXPECTED_TYPE
	jmp parser_fail
.expectedFunction:
	lda #PARSE_EXPECTED_FUNCTION
	jmp parser_fail
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

;;; parser_next
;;; Replace currentToken. Scanner failures become one parser-level failure path.
parser_next:
	jsr next_token
	lda currentTokenKind
	cmp #TOKEN_ERROR
	bne .ok
	lda #PARSE_SCANNER_ERROR
	sta parserError
	clc
	rts
.ok:
	sec
	rts

parser_fail:
	sta parserError
	clc
	rts

;;; is_type_token
;;; A=token kind, preserved. Carry set for char/int/unsigned.
is_type_token:
	cmp #TOKEN_KW_CHAR
	beq .yes
	cmp #TOKEN_KW_INT
	beq .yes
	cmp #TOKEN_KW_UNSIGNED
	beq .yes
	clc
	rts
.yes:
	sec
	rts

;;; parse_decl_type
;;; currentToken is char/int/unsigned.  On success declType is set and current
;;; token is the token after the complete type spelling.  Only char may be
;;; followed by '*'.
parse_decl_type:
	lda currentTokenKind
	cmp #TOKEN_KW_CHAR
	beq .char
	cmp #TOKEN_KW_INT
	beq .int
	cmp #TOKEN_KW_UNSIGNED
	beq .unsigned
	lda #PARSE_EXPECTED_TYPE
	jmp parser_fail
.char:
	lda #TYPE_CHAR
	sta declType
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'*'
	bne .done
	lda #TYPE_CHAR_PTR
	sta declType
	jsr parser_next
	rts
.int:
	lda #TYPE_INT
	sta declType
	jsr parser_next
	rts
.unsigned:
	lda #TYPE_UNSIGNED
	sta declType
	jsr parser_next
	rts
.done:
	sec
.failed:
	rts

;;; parse_top_level_declaration
;;; Resolve the one ambiguity Phase 1 has at top level: `int name (` starts a
;;; function definition; every other declarator is a global.
parse_top_level_declaration:
	jsr parse_decl_type
	bcc .failed
	lda currentTokenKind
	cmp #TOKEN_IDENTIFIER
	beq .name
	lda #PARSE_EXPECTED_IDENTIFIER
	jmp parser_fail

.name:
	jsr lookup_persistent_token
	bcc .unique
	lda #PARSE_DUPLICATE_SYMBOL
	jmp parser_fail
.unique:
	jsr reserve_persistent_name
	bcs .reserved
	lda persistentCount
	cmp #PERSISTENT_SYMBOL_CAPACITY
	bcc .nameFull
	lda #PARSE_SYMBOL_CAPACITY
	jmp parser_fail
.nameFull:
	lda #PARSE_NAME_CAPACITY
	jmp parser_fail
.reserved:
	stx pendingPersistentIndex
	lda declType
	sta persistentType,x
	jsr parser_next
	bcc .failed

	lda currentTokenKind
	cmp #'('
	beq .function
	lda translationInFunctions
	beq .global
	lda #PARSE_GLOBAL_AFTER_FUNCTION
	jmp parser_fail
.global:
	jmp parse_global_declaration

.function:
	lda declType
	cmp #TYPE_INT
	beq .functionTypeOk
	lda #PARSE_BAD_FUNCTION
	jmp parser_fail
.functionTypeOk:
	lda translationInFunctions
	bne .alreadyFunctions
	lda #$01
	sta translationInFunctions
	lda bssOffset
	sta zeroRequiredEnd
	lda bssOffset+1
	sta zeroRequiredEnd+1
.alreadyFunctions:
	jmp parse_function_definition
.failed:
	clc
	rts

;;; ---------------------------------------------------------------------------
;;; Globals
;;; ---------------------------------------------------------------------------

parse_global_declaration:
	lda currentTokenKind
	cmp #'['
	beq .array
	jmp parse_global_scalar
.array:
	lda declType
	cmp #TYPE_CHAR_PTR
	bne .arrayTypeOk
	lda #PARSE_BAD_DECLARATOR
	jmp parser_fail
.arrayTypeOk:
	jmp parse_global_array

parse_global_scalar:
	ldx pendingPersistentIndex
	lda #$00
	sta persistentArrayLengthLo,x
	sta persistentArrayLengthHi,x
	lda currentTokenKind
	cmp #';'
	beq .uninitialized
	cmp #'='
	beq .initialized
	lda #PARSE_BAD_DECLARATOR
	jmp parser_fail

.uninitialized:
	lda declType
	jsr set_alloc_size_for_type
	jsr allocate_bss
	bcs .allocated
	lda #PARSE_BSS_OVERFLOW
	jmp parser_fail
.allocated:
	ldx pendingPersistentIndex
	lda #SYMBOL_GLOBAL_BSS
	sta persistentKind,x
	lda allocOffset
	sta persistentStorageOffsetLo,x
	lda allocOffset+1
	sta persistentStorageOffsetHi,x
	jsr emit_persistent_checked
	bcc .failed
	jsr commit_persistent_symbol
	jsr parser_next
	rts

.initialized:
	lda declType
	cmp #TYPE_CHAR_PTR
	bne .scalarInitAllowed
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.scalarInitAllowed:
	jsr parser_next
	bcc .failed
	jsr parse_static_constant
	bcc .failed
	jsr constant_fits_decl_type
	bcc .range
	ldx pendingPersistentIndex
	lda #SYMBOL_GLOBAL_DATA
	sta persistentKind,x
	lda #$00
	sta persistentStorageOffsetLo,x
	sta persistentStorageOffsetHi,x
	jsr emit_persistent_checked
	bcc .failed
	jsr emit_constant_for_decl_type
	bcc .failed
	lda currentTokenKind
	cmp #';'
	beq .scalarDone
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.scalarDone:
	jsr commit_persistent_symbol
	jsr parser_next
	rts
.range:
	lda #PARSE_VALUE_RANGE
	jmp parser_fail
.failed:
	clc
	rts

parse_global_array:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #TOKEN_INTEGER
	beq .sizeToken
	lda #PARSE_BAD_ARRAY_SIZE
	jmp parser_fail
.sizeToken:
	lda currentTokenValue
	sta arrayLength
	lda currentTokenValue+1
	sta arrayLength+1
	ora arrayLength
	bne .positive
	lda #PARSE_BAD_ARRAY_SIZE
	jmp parser_fail
.positive:
	ldx pendingPersistentIndex
	lda arrayLength
	sta persistentArrayLengthLo,x
	lda arrayLength+1
	sta persistentArrayLengthHi,x
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #']'
	beq .closed
	lda #PARSE_BAD_DECLARATOR
	jmp parser_fail
.closed:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #';'
	beq .uninitialized
	cmp #'='
	beq .initialized
	lda #PARSE_BAD_DECLARATOR
	jmp parser_fail

.uninitialized:
	jsr set_alloc_size_for_array
	bcc .bssOverflow
	jsr allocate_bss
	bcc .bssOverflow
	ldx pendingPersistentIndex
	lda #SYMBOL_ARRAY_BSS
	sta persistentKind,x
	lda allocOffset
	sta persistentStorageOffsetLo,x
	lda allocOffset+1
	sta persistentStorageOffsetHi,x
	jsr emit_persistent_checked
	bcc .failed
	jsr commit_persistent_symbol
	jsr parser_next
	rts
.bssOverflow:
	lda #PARSE_BSS_OVERFLOW
	jmp parser_fail

.initialized:
	jsr parser_next
	bcc .failed
	ldx pendingPersistentIndex
	lda #SYMBOL_ARRAY_DATA
	sta persistentKind,x
	lda #$00
	sta persistentStorageOffsetLo,x
	sta persistentStorageOffsetHi,x
	jsr emit_persistent_checked
	bcc .failed

	lda currentTokenKind
	cmp #TOKEN_STRING
	beq .string
	cmp #'{' 
	beq .numeric
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.string:
	lda declType
	cmp #TYPE_CHAR
	beq .charString
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.charString:
	jsr emit_string_array_initializer
	bcc .failed
	jmp .initializerDone
.numeric:
	jsr emit_numeric_array_initializer
	bcc .failed

.initializerDone:
	lda currentTokenKind
	cmp #';'
	beq .arrayDone
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.arrayDone:
	jsr commit_persistent_symbol
	jsr parser_next
	rts
.failed:
	clc
	rts

emit_numeric_array_initializer:
	lda #$00
	sta initializerCount
	sta initializerCount+1
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'}'
	beq .fill

.element:
	jsr initializer_has_room
	bcc .tooMany
	jsr parse_static_constant
	bcc .failed
	jsr constant_fits_decl_type
	bcc .range
	jsr emit_constant_for_decl_type
	bcc .failed
	inc initializerCount
	bne .separator
	inc initializerCount+1
.separator:
	lda currentTokenKind
	cmp #'}'
	beq .fill
	cmp #','
	beq .next
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.next:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'}'
	bne .element
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail

.fill:
	jsr emit_remaining_array_zeros
	bcc .failed
	jsr parser_next
	rts
.tooMany:
	lda #PARSE_TOO_MANY_INITIALIZERS
	jmp parser_fail
.range:
	lda #PARSE_VALUE_RANGE
	jmp parser_fail
.failed:
	clc
	rts

initializer_has_room:
	lda initializerCount+1
	cmp arrayLength+1
	bcc .yes
	bne .no
	lda initializerCount
	cmp arrayLength
	bcc .yes
.no:
	clc
	rts
.yes:
	sec
	rts

emit_remaining_array_zeros:
.loop:
	lda initializerCount+1
	cmp arrayLength+1
	bne .more
	lda initializerCount
	cmp arrayLength
	beq .done
.more:
	jsr emit_zero_for_decl_type
	bcc .failed
	inc initializerCount
	bne .loop
	inc initializerCount+1
	jmp .loop
.done:
	sec
.failed:
	rts

emit_string_array_initializer:
	lda #$00
	sta initializerCount+1
	lda currentTokenLength
	sta initializerCount
	inc initializerCount
	bne .counted
	inc initializerCount+1
.counted:
	lda initializerCount+1
	cmp arrayLength+1
	bcc .fits
	bne .tooLong
	lda initializerCount
	cmp arrayLength
	bcc .fits
	beq .fits
.tooLong:
	lda #PARSE_STRING_TOO_LONG
	jmp parser_fail

.fits:
	ldy #$00
.bytes:
	cpy currentTokenLength
	beq .nul
	lda currentTokenText,y
	sty stringEmitIndex
	jsr emit_static_byte
	bcc .emitFail
	ldy stringEmitIndex
	iny
	jmp .bytes
.nul:
	lda #$00
	jsr emit_static_byte
	bcc .emitFail
	jsr emit_remaining_array_zeros
	bcc .failed
	jsr parser_next
	rts
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.failed:
	clc
	rts

;;; Phase 1 deliberately has no general constant-expression evaluator.  Static
;;; initialization accepts one integer/character literal optionally preceded by
;;; unary '-'.  Leaves current token after the constant.
parse_static_constant:
	lda #$00
	sta constantNegative
	lda currentTokenKind
	cmp #'-'
	bne .literal
	lda #$01
	sta constantNegative
	jsr parser_next
	bcc .failed
.literal:
	lda currentTokenKind
	cmp #TOKEN_INTEGER
	beq .have
	cmp #TOKEN_CHARACTER
	beq .have
	lda #PARSE_BAD_CONSTANT
	jmp parser_fail
.have:
	lda currentTokenValue
	sta constantMagnitude
	sta constantValue
	lda currentTokenValue+1
	sta constantMagnitude+1
	sta constantValue+1
	lda constantNegative
	beq .advance
	lda constantValue
	eor #$ff
	clc
	adc #$01
	sta constantValue
	lda constantValue+1
	eor #$ff
	adc #$00
	sta constantValue+1
.advance:
	jsr parser_next
	rts
.failed:
	clc
	rts

constant_fits_decl_type:
	lda declType
	cmp #TYPE_CHAR
	beq .char
	cmp #TYPE_INT
	beq .int
	cmp #TYPE_UNSIGNED
	beq .unsigned
	clc
	rts
.char:
	lda constantNegative
	bne .no
	lda constantValue+1
	beq .yes
	clc
	rts
.int:
	lda constantNegative
	beq .positiveInt
	lda constantMagnitude+1
	cmp #$80
	bcc .yes
	bne .no
	lda constantMagnitude
	beq .yes
.no:
	clc
	rts
.positiveInt:
	lda constantValue+1
	bmi .no
.yes:
	sec
	rts
.unsigned:
	lda constantNegative
	beq .yes
	clc
	rts

emit_constant_for_decl_type:
	lda constantValue
	jsr emit_static_byte
	bcc .emitFail
	lda declType
	cmp #TYPE_CHAR
	beq .done
	lda constantValue+1
	jsr emit_static_byte
	bcc .emitFail
.done:
	sec
	rts
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

emit_zero_for_decl_type:
	lda #$00
	jsr emit_static_byte
	bcc .emitFail
	lda declType
	cmp #TYPE_CHAR
	beq .done
	lda #$00
	jsr emit_static_byte
	bcc .emitFail
.done:
	sec
	rts
.emitFail:
	lda #PARSE_EMIT_ERROR
	jmp parser_fail

emit_persistent_checked:
	ldx pendingPersistentIndex
	jsr emit_persistent_symbol
	bcs .ok
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.ok:
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Function definitions and current-function storage
;;; ---------------------------------------------------------------------------

parse_function_definition:
	ldx pendingPersistentIndex
	stx currentFunctionIndex
	lda #SYMBOL_FUNCTION
	sta persistentKind,x
	lda #TYPE_INT
	sta persistentType,x
	lda #$00
	sta persistentStorageOffsetLo,x
	sta persistentStorageOffsetHi,x
	sta persistentArrayLengthLo,x
	sta persistentArrayLengthHi,x
	lda parameterMetaCount
	sta persistentParamStart,x
	lda #$00
	sta persistentParamCount,x
	jsr discard_current_symbols

	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #')'
	beq .parametersDone

.parameter:
	jsr parse_function_parameter
	bcc .failed
	ldx pendingPersistentIndex
	inc persistentParamCount,x
	lda currentTokenKind
	cmp #')'
	beq .parametersDone
	cmp #','
	beq .nextParameter
	lda #PARSE_BAD_FUNCTION
	jmp parser_fail
.nextParameter:
	jsr parser_next
	bcc .failed
	jmp .parameter

.parametersDone:
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'{' 
	beq .body
	lda #PARSE_BAD_FUNCTION
	jmp parser_fail
.body:
	jsr emit_persistent_checked
	bcc .failed
	jsr parser_next
	bcc .failed
	jsr parse_function_locals
	bcc .failed
	jsr skip_function_statements
	bcc .failed

	jsr commit_persistent_symbol
	inc userFunctionCount
	jsr discard_current_symbols
	sec
	rts
.failed:
	clc
	rts

parse_function_parameter:
	jsr parse_decl_type
	bcc .failed
	lda currentTokenKind
	cmp #TOKEN_IDENTIFIER
	beq .name
	lda #PARSE_EXPECTED_IDENTIFIER
	jmp parser_fail
.name:
	jsr lookup_current_token
	bcc .unique
	lda #PARSE_DUPLICATE_SYMBOL
	jmp parser_fail
.unique:
	lda parameterMetaCount
	cmp #PARAM_META_CAPACITY
	bcc .paramSpace
	lda #PARSE_PARAMETER_CAPACITY
	jmp parser_fail
.paramSpace:
	jsr reserve_current_name
	bcs .reserved
	lda currentCount
	cmp #CURRENT_SYMBOL_CAPACITY
	bcc .nameFull
	lda #PARSE_SYMBOL_CAPACITY
	jmp parser_fail
.nameFull:
	lda #PARSE_NAME_CAPACITY
	jmp parser_fail
.reserved:
	stx pendingCurrentIndex
	lda #CURRENT_PARAMETER
	sta currentKind,x
	lda declType
	sta currentType,x
	jsr set_alloc_size_for_type
	jsr allocate_bss
	bcs .allocated
	lda #PARSE_BSS_OVERFLOW
	jmp parser_fail
.allocated:
	ldx pendingCurrentIndex
	lda allocOffset
	sta currentStorageOffsetLo,x
	lda allocOffset+1
	sta currentStorageOffsetHi,x
	jsr append_parameter_metadata
	bcc .paramFull
	jsr emit_current_checked
	bcc .failed
	jsr commit_current_symbol
	jsr parser_next
	rts
.paramFull:
	lda #PARSE_PARAMETER_CAPACITY
	jmp parser_fail
.failed:
	clc
	rts

parse_function_locals:
.loop:
	lda currentTokenKind
	jsr is_type_token
	bcc .done
	jsr parse_one_local
	bcc .failed
	jmp .loop
.done:
	sec
.failed:
	rts

parse_one_local:
	jsr parse_decl_type
	bcc .failed
	lda currentTokenKind
	cmp #TOKEN_IDENTIFIER
	beq .name
	lda #PARSE_EXPECTED_IDENTIFIER
	jmp parser_fail
.name:
	jsr lookup_current_token
	bcc .unique
	lda #PARSE_DUPLICATE_SYMBOL
	jmp parser_fail
.unique:
	jsr reserve_current_name
	bcs .reserved
	lda currentCount
	cmp #CURRENT_SYMBOL_CAPACITY
	bcc .nameFull
	lda #PARSE_SYMBOL_CAPACITY
	jmp parser_fail
.nameFull:
	lda #PARSE_NAME_CAPACITY
	jmp parser_fail
.reserved:
	stx pendingCurrentIndex
	lda #CURRENT_LOCAL
	sta currentKind,x
	lda declType
	sta currentType,x
	jsr set_alloc_size_for_type
	jsr allocate_bss
	bcs .allocated
	lda #PARSE_BSS_OVERFLOW
	jmp parser_fail
.allocated:
	ldx pendingCurrentIndex
	lda allocOffset
	sta currentStorageOffsetLo,x
	lda allocOffset+1
	sta currentStorageOffsetHi,x
	jsr emit_current_checked
	bcc .failed
	jsr parser_next
	bcc .failed
	lda currentTokenKind
	cmp #'['
	beq .localArray
	cmp #'='
	beq .initializer
	cmp #';'
	beq .commit
	lda #PARSE_BAD_DECLARATOR
	jmp parser_fail
.localArray:
	lda #PARSE_LOCAL_ARRAY
	jmp parser_fail
.initializer:
	jsr parser_next
	bcc .failed
	jsr validate_local_initializer
	bcc .failed
.commit:
	jsr commit_current_symbol
	jsr parser_next
	rts
.failed:
	clc
	rts

;;; Temporary #54 hook: consume a non-empty expression up to ';' and apply only
;;; declaration-before-use to identifier tokens.  #55 replaces this call site
;;; with the real non-recursive expression engine and store.
validate_local_initializer:
	lda currentTokenKind
	cmp #';'
	bne .loop
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.loop:
	lda currentTokenKind
	cmp #TOKEN_EOF
	beq .bad
	cmp #'{' 
	beq .bad
	cmp #'}'
	beq .bad
	cmp #';'
	beq .done
	cmp #TOKEN_IDENTIFIER
	bne .advance
	jsr lookup_symbol
	bcs .advance
	lda #PARSE_UNDECLARED
	jmp parser_fail
.advance:
	jsr parser_next
	bcc .failed
	jmp .loop
.done:
	sec
	rts
.bad:
	lda #PARSE_BAD_INITIALIZER
	jmp parser_fail
.failed:
	clc
	rts

;;; This is not a statement parser. It only finds the matching function brace so
;;; later definitions can be seen, while enforcing rules already owned by #54:
;;; no later declarations and immediate failure for undeclared identifiers.
skip_function_statements:
	lda #$00
	sta bodyBraceDepth
.loop:
	lda currentTokenKind
	cmp #TOKEN_EOF
	beq .unterminated
	jsr is_type_token
	bcs .lateLocal
	lda currentTokenKind
	cmp #TOKEN_IDENTIFIER
	bne .notIdentifier
	jsr lookup_symbol
	bcs .advance
	lda #PARSE_UNDECLARED
	jmp parser_fail
.notIdentifier:
	lda currentTokenKind
	cmp #'{' 
	beq .openBrace
	cmp #'}'
	beq .closeBrace
.advance:
	jsr parser_next
	bcc .failed
	jmp .loop
.openBrace:
	inc bodyBraceDepth
	beq .unterminated
	jmp .advance
.closeBrace:
	lda bodyBraceDepth
	beq .functionDone
	dec bodyBraceDepth
	jmp .advance
.functionDone:
	jsr parser_next
	rts
.lateLocal:
	lda #PARSE_LATE_LOCAL
	jmp parser_fail
.unterminated:
	lda #PARSE_UNTERMINATED_FUNCTION
	jmp parser_fail
.failed:
	clc
	rts

emit_current_checked:
	ldx pendingCurrentIndex
	jsr emit_current_symbol
	bcs .ok
	lda #PARSE_EMIT_ERROR
	jmp parser_fail
.ok:
	sec
	rts

;;; Parser state kept outside the reusable scanner token.
parserError:		byte PARSE_OK
translationInFunctions:	byte 0
pendingPersistentIndex:	byte 0
declType:		byte TYPE_INT
arrayLength:		word 0
initializerCount:	word 0
constantValue:		word 0
constantMagnitude:	word 0
constantNegative:	byte 0
bodyBraceDepth:		byte 0
stringEmitIndex:	byte 0
