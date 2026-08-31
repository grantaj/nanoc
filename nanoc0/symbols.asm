;;; symbols.asm
;;;
;;; Nano C Phase 1 symbol and static-storage state.
;;;
;;; There are only two symbol areas:
;;;   - persistent globals and already-defined functions;
;;;   - parameters/locals for the function currently being compiled.
;;;
;;; Both are linear bounded arrays. Names live in one owned byte pool. Each
;;; owned name is stored as [length][bytes...], so a symbol record needs only a
;;; pool offset rather than a separate length byte.
;;;
;;; Current-function names are allocated after persistentNameUsed. Ending a
;;; function resets namePoolNext to that boundary and reuses those bytes.
;;;
;;; lookup_symbol always checks current-function names first, so a local or
;;; parameter may shadow a global. No other scope machinery exists.
;;;
;;; Capacity is based on the real bootstrap/ass.c rather than an arbitrary round
;;; number. At this revision that source requires, including the five runtime
;;; functions:
;;;
;;;   persistent symbols       129    capacity 160
;;;   persistent name bytes   2044    capacity 2304
;;;   parameter type entries   105    capacity 128
;;;   max current symbols       11    capacity 32
;;;   max current name bytes    95    uses the unused tail of the name pool
;;;
;;; tests/test_nanoc0_bootstrap parses bootstrap/ass.c natively, so these
;;; assumptions fail in CI if the bootstrap outgrows them.

DECL_PTR = $fe

TYPE_CHAR       = 1
TYPE_INT        = 2
TYPE_UNSIGNED   = 3
TYPE_CHAR_PTR   = 4

;;; Persistent kind records source meaning only. Whether a global was emitted as
;;; BSS or initialized data matters only at its declaration and is not retained.
SYMBOL_GLOBAL           = 1
SYMBOL_ARRAY            = 2
SYMBOL_FUNCTION         = 3
SYMBOL_RUNTIME_FUNCTION = 4

SYMBOL_AREA_NONE       = 0
SYMBOL_AREA_CURRENT    = 1
SYMBOL_AREA_PERSISTENT = 2

PERSISTENT_SYMBOL_CAPACITY = 160
CURRENT_SYMBOL_CAPACITY    = 32
NAME_POOL_CAPACITY         = 2304
PARAM_META_CAPACITY        = 128

;;; Six bytes per persistent entry, three per current entry, one byte per saved
;;; parameter type and the owned-name pool. Production nanoc0 places these 3488
;;; mutable bytes at $8100 instead of serialising zero-filled workspace into the
;;; program image. Focused native tests may still use the in-image form.
SYMBOL_WORKSPACE_BYTES = 3488
NANOC_SYMBOL_WORKSPACE = $8100

RUNTIME_SYMBOL_COUNT = 5
RUNTIME_NAME_BYTES   = 44
RUNTIME_PARAM_COUNT  = 8

;;; reset_symbol_state
;;; Keep the five fixed runtime function entries and discard every source name,
;;; current-function entry and BSS allocation from the previous translation.
;;; bssBase is supplied by the wrapper/test before parsing begins.
reset_symbol_state:
	ifdef NANOC0_FIXED_WORKSPACE
	jsr initialize_runtime_symbols
	endif
	lda #RUNTIME_SYMBOL_COUNT
	sta persistentCount
	lda #RUNTIME_PARAM_COUNT
	sta parameterMetaCount
	lda #$00
	sta currentCount
	sta userFunctionCount
	sta bssOffset
	sta bssOffset+1
	sta zeroRequiredEnd
	sta zeroRequiredEnd+1
	lda #<RUNTIME_NAME_BYTES
	sta persistentNameUsed
	sta namePoolNext
	lda #>RUNTIME_NAME_BYTES
	sta persistentNameUsed+1
	sta namePoolNext+1
	rts

;;; The production workspace starts as arbitrary RAM, so restore only the fixed
;;; runtime prefixes that lookup/call parsing needs. All source-owned tails are
;;; bounded by counts and are overwritten before becoming visible.
	ifdef NANOC0_FIXED_WORKSPACE
initialize_runtime_symbols:
	ldx #RUNTIME_SYMBOL_COUNT-1
.symbols:
	lda runtimeNameOffsetLoInit,x
	sta persistentNameOffsetLo,x
	lda runtimeNameOffsetHiInit,x
	sta persistentNameOffsetHi,x
	lda runtimeKindInit,x
	sta persistentKind,x
	lda runtimeTypeInit,x
	sta persistentType,x
	lda runtimeParamStartInit,x
	sta persistentParamStart,x
	lda runtimeParamCountInit,x
	sta persistentParamCount,x
	dex
	bpl .symbols

	ldx #RUNTIME_PARAM_COUNT-1
.params:
	lda runtimeParamTypeInit,x
	sta parameterType,x
	dex
	bpl .params

	ldx #RUNTIME_NAME_BYTES-1
.names:
	lda runtimeNamesInit,x
	sta namePool,x
	dex
	bpl .names
	rts
	endif

;;; store_persistent_name
;;; persistentCount is both the number of visible persistent symbols and the
;;; slot being constructed. Copy currentTokenText into that slot's owned name.
;;; Lookup still stops before this slot until make_persistent_visible increments
;;; persistentCount. Carry clear means symbol or name capacity is exhausted.
store_persistent_name:
	ldx persistentCount
	cpx #PERSISTENT_SYMBOL_CAPACITY
	bcc .space
	clc
	rts
.space:
	jsr copy_token_to_name_pool
	bcc .full
	lda nameCopyStart
	sta persistentNameOffsetLo,x
	lda nameCopyStart+1
	sta persistentNameOffsetHi,x
	lda namePoolNext
	sta persistentNameUsed
	lda namePoolNext+1
	sta persistentNameUsed+1
	sec
	rts
.full:
	clc
	rts

;;; store_current_name
;;; currentCount is both the number of visible current-function symbols and the
;;; slot being constructed. A local initializer therefore cannot see its own
;;; slot until make_current_visible increments currentCount.
store_current_name:
	ldx currentCount
	cpx #CURRENT_SYMBOL_CAPACITY
	bcc .space
	clc
	rts
.space:
	jsr copy_token_to_name_pool
	bcc .full
	lda nameCopyStart
	sta currentNameOffsetLo,x
	lda nameCopyStart+1
	sta currentNameOffsetHi,x
	sec
	rts
.full:
	clc
	rts

;;; copy_token_to_name_pool
;;; Store [length][currentTokenText...] at namePoolNext. X is preserved so a
;;; caller may keep its symbol index there. Carry clear means the bounded pool
;;; would overflow.
copy_token_to_name_pool:
	lda namePoolNext
	sta nameCopyStart
	clc
	adc currentTokenLength
	sta nameCopyEnd
	lda namePoolNext+1
	sta nameCopyStart+1
	adc #$00
	sta nameCopyEnd+1
	inc nameCopyEnd
	bne .checkCapacity
	inc nameCopyEnd+1

.checkCapacity:
	lda nameCopyEnd+1
	cmp #>NAME_POOL_CAPACITY
	bcc .fits
	bne .full
	lda nameCopyEnd
	cmp #<NAME_POOL_CAPACITY
	bcc .fits
	beq .fits
.full:
	clc
	rts

.fits:
	clc
	lda #<namePool
	adc nameCopyStart
	sta DECL_PTR
	lda #>namePool
	adc nameCopyStart+1
	sta DECL_PTR+1

	ldy #$00
	lda currentTokenLength
	sta (DECL_PTR),y
	inc DECL_PTR
	bne .copyStart
	inc DECL_PTR+1
.copyStart:
	ldy #$00
.copy:
	cpy currentTokenLength
	beq .done
	lda currentTokenText,y
	sta (DECL_PTR),y
	iny
	jmp .copy
.done:
	lda nameCopyEnd
	sta namePoolNext
	lda nameCopyEnd+1
	sta namePoolNext+1
	sec
	rts

;;; The counts are the visibility boundary. No separate pending-symbol state is
;;; required: filling slot[count] is harmless until the count is incremented.
make_persistent_visible:
	inc persistentCount
	rts

make_current_visible:
	inc currentCount
	rts

;;; discard_current_symbols
;;; Current symbol records need not be cleared; count and the name-pool boundary
;;; make the old bytes unreachable and reusable.
discard_current_symbols:
	lda #$00
	sta currentCount
	lda persistentNameUsed
	sta namePoolNext
	lda persistentNameUsed+1
	sta namePoolNext+1
	rts

;;; lookup_symbol
;;; Compare currentTokenText with visible names.
;;; Carry set: X is the matching index and lookupArea identifies its table.
;;; Carry clear: the name is undeclared.
lookup_symbol:
	jsr lookup_current_token
	bcc .persistent
	lda #SYMBOL_AREA_CURRENT
	sta lookupArea
	sec
	rts
.persistent:
	jsr lookup_persistent_token
	bcc .missing
	lda #SYMBOL_AREA_PERSISTENT
	sta lookupArea
	sec
	rts
.missing:
	lda #SYMBOL_AREA_NONE
	sta lookupArea
	clc
	rts

;;; lookup_current_token
;;; Carry set with X=current symbol index on an exact byte-for-byte match.
lookup_current_token:
	ldx #$00
.loop:
	cpx currentCount
	beq .missing
	lda currentNameOffsetLo,x
	sta nameCompareOffset
	lda currentNameOffsetHi,x
	sta nameCompareOffset+1
	jsr token_equals_pool_name
	bcs .found
	inx
	jmp .loop
.found:
	sec
	rts
.missing:
	clc
	rts

;;; lookup_persistent_token
;;; Carry set with X=persistent symbol index on an exact match.
lookup_persistent_token:
	ldx #$00
.loop:
	cpx persistentCount
	beq .missing
	lda persistentNameOffsetLo,x
	sta nameCompareOffset
	lda persistentNameOffsetHi,x
	sta nameCompareOffset+1
	jsr token_equals_pool_name
	bcs .found
	inx
	jmp .loop
.found:
	sec
	rts
.missing:
	clc
	rts

;;; token_equals_pool_name
;;; X is preserved naturally because Y performs the byte walk. Carry set means
;;; currentTokenText equals the length-prefixed pool name at nameCompareOffset.
token_equals_pool_name:
	clc
	lda #<namePool
	adc nameCompareOffset
	sta DECL_PTR
	lda #>namePool
	adc nameCompareOffset+1
	sta DECL_PTR+1

	ldy #$00
	lda (DECL_PTR),y
	cmp currentTokenLength
	bne .different
	inc DECL_PTR
	bne .compareStart
	inc DECL_PTR+1
.compareStart:
	ldy #$00
.compare:
	cpy currentTokenLength
	beq .equal
	lda (DECL_PTR),y
	cmp currentTokenText,y
	bne .different
	iny
	jmp .compare
.equal:
	sec
	rts
.different:
	clc
	rts

;;; allocate_bss
;;; allocSize is a 16-bit byte count.
;;; Carry set: allocOffset is the old BSS offset and allocation is committed.
;;; Carry clear: the offset itself or NC_BSS+new offset would wrap 16 bits.
;;;
;;; bssOffset is the single authoritative allocation position. Absolute target
;;; addresses are derived from bssBase only when checking for wrap; they are not
;;; retained as a second copy of the same position.
allocate_bss:
	lda bssOffset
	sta allocOffset
	lda bssOffset+1
	sta allocOffset+1

	clc
	lda bssOffset
	adc allocSize
	sta allocNextOffset
	lda bssOffset+1
	adc allocSize+1
	sta allocNextOffset+1
	bcs .overflow

	clc
	lda bssBase
	adc allocNextOffset
	lda bssBase+1
	adc allocNextOffset+1
	bcs .overflow

	lda allocNextOffset
	sta bssOffset
	lda allocNextOffset+1
	sta bssOffset+1
	sec
	rts
.overflow:
	clc
	rts

;;; set_alloc_size_for_type
;;; A=TYPE_*. allocSize receives the exact target width.
set_alloc_size_for_type:
	cmp #TYPE_CHAR
	bne .word
	lda #$01
	sta allocSize
	lda #$00
	sta allocSize+1
	rts
.word:
	lda #$02
	sta allocSize
	lda #$00
	sta allocSize+1
	rts

;;; set_alloc_size_for_array
;;; declType and arrayLength describe a global array.
;;; Carry clear means the byte count itself exceeds 16 bits.
set_alloc_size_for_array:
	lda arrayLength
	sta allocSize
	lda arrayLength+1
	sta allocSize+1
	lda declType
	cmp #TYPE_CHAR
	beq .done
	asl allocSize
	rol allocSize+1
	bcs .overflow
.done:
	sec
	rts
.overflow:
	clc
	rts

;;; append_parameter_metadata
;;; Retain only the parameter type needed by later callers. The parameter's
;;; storage label is deterministic from function symbol + argument ordinal, so
;;; retaining the numeric NC_BSS address would duplicate information already
;;; emitted to assembly. The parameter being constructed is slot currentCount.
append_parameter_metadata:
	ldx parameterMetaCount
	cpx #PARAM_META_CAPACITY
	bcc .space
	clc
	rts
.space:
	ldy currentCount
	lda currentType,y
	sta parameterType,x
	inc parameterMetaCount
	sec
	rts

;;; ---------------------------------------------------------------------------
;;; Symbol tables
;;; ---------------------------------------------------------------------------

persistentCount:	byte RUNTIME_SYMBOL_COUNT
currentCount:		byte 0
userFunctionCount:	byte 0
lookupArea:		byte SYMBOL_AREA_NONE
currentFunctionIndex:	byte 0
parameterMetaCount:	byte RUNTIME_PARAM_COUNT
persistentNameUsed:	word RUNTIME_NAME_BYTES
namePoolNext:		word RUNTIME_NAME_BYTES

;;; Production uses an explicit RAM workspace. There is no zero-filled payload in
;;; nanoc0.prg for these arrays. The address arithmetic below is intentionally
;;; literal and auditable; this is the whole symbol/name memory map.
	ifdef NANOC0_FIXED_WORKSPACE
symbolWorkspaceStart = NANOC_SYMBOL_WORKSPACE
persistentNameOffsetLo = symbolWorkspaceStart
persistentNameOffsetHi = persistentNameOffsetLo+PERSISTENT_SYMBOL_CAPACITY
persistentKind         = persistentNameOffsetHi+PERSISTENT_SYMBOL_CAPACITY
persistentType         = persistentKind+PERSISTENT_SYMBOL_CAPACITY
persistentParamStart   = persistentType+PERSISTENT_SYMBOL_CAPACITY
persistentParamCount   = persistentParamStart+PERSISTENT_SYMBOL_CAPACITY
currentNameOffsetLo    = persistentParamCount+PERSISTENT_SYMBOL_CAPACITY
currentNameOffsetHi    = currentNameOffsetLo+CURRENT_SYMBOL_CAPACITY
currentType            = currentNameOffsetHi+CURRENT_SYMBOL_CAPACITY
parameterType          = currentType+CURRENT_SYMBOL_CAPACITY
namePool               = parameterType+PARAM_META_CAPACITY
symbolWorkspaceEnd     = namePool+NAME_POOL_CAPACITY
	else
symbolWorkspaceStart:

persistentNameOffsetLo:
	byte 0,8,16,26,35
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentNameOffsetHi:
	byte 0,0,0,0,0
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentKind:
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentType:
	byte TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentParamStart:
	byte 0,2,3,5,7
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentParamCount:
	byte 2,1,2,2,1
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT

currentNameOffsetLo:	ds CURRENT_SYMBOL_CAPACITY
currentNameOffsetHi:	ds CURRENT_SYMBOL_CAPACITY
currentType:		ds CURRENT_SYMBOL_CAPACITY

parameterType:
	byte TYPE_CHAR_PTR,TYPE_INT
	byte TYPE_INT
	byte TYPE_CHAR_PTR,TYPE_INT
	byte TYPE_INT,TYPE_INT
	byte TYPE_INT
	ds PARAM_META_CAPACITY-RUNTIME_PARAM_COUNT

namePool:
	byte 7,'i','o','_','o','p','e','n'
	byte 7,'i','o','_','r','e','a','d'
	byte 9,'i','o','_','c','r','e','a','t','e'
	byte 8,'i','o','_','w','r','i','t','e'
	byte 8,'i','o','_','c','l','o','s','e'
	ds NAME_POOL_CAPACITY-RUNTIME_NAME_BYTES
symbolWorkspaceEnd:
	endif

;;; Immutable bootstrap values copied into the fixed workspace on each real
;;; compile. They are tiny; the large source-dependent tails stay RAM-only.
	ifdef NANOC0_FIXED_WORKSPACE
runtimeNameOffsetLoInit:	byte 0,8,16,26,35
runtimeNameOffsetHiInit:	byte 0,0,0,0,0
runtimeKindInit:
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
runtimeTypeInit:		byte TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT
runtimeParamStartInit:	byte 0,2,3,5,7
runtimeParamCountInit:	byte 2,1,2,2,1
runtimeParamTypeInit:
	byte TYPE_CHAR_PTR,TYPE_INT
	byte TYPE_INT
	byte TYPE_CHAR_PTR,TYPE_INT
	byte TYPE_INT,TYPE_INT
	byte TYPE_INT
runtimeNamesInit:
	byte 7,'i','o','_','o','p','e','n'
	byte 7,'i','o','_','r','e','a','d'
	byte 9,'i','o','_','c','r','e','a','t','e'
	byte 8,'i','o','_','w','r','i','t','e'
	byte 8,'i','o','_','c','l','o','s','e'
	endif

;;; Static BSS allocation state.
bssBase:		word $5000
bssOffset:		word 0
zeroRequiredEnd:	word 0
allocSize:		word 0
allocOffset:		word 0
allocNextOffset:	word 0

;;; Shared symbol scratch.
nameCopyStart:		word 0
nameCopyEnd:		word 0
nameCompareOffset:	word 0
