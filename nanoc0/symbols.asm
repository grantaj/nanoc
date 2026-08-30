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

DECL_TMP = $fc
DECL_PTR = $fe

TYPE_CHAR       = 1
TYPE_INT        = 2
TYPE_UNSIGNED   = 3
TYPE_CHAR_PTR   = 4

SYMBOL_GLOBAL_BSS       = 1
SYMBOL_GLOBAL_DATA      = 2
SYMBOL_ARRAY_BSS        = 3
SYMBOL_ARRAY_DATA       = 4
SYMBOL_FUNCTION         = 5
SYMBOL_RUNTIME_FUNCTION = 6

SYMBOL_AREA_NONE       = 0
SYMBOL_AREA_CURRENT    = 1
SYMBOL_AREA_PERSISTENT = 2

PERSISTENT_SYMBOL_CAPACITY = 160
CURRENT_SYMBOL_CAPACITY    = 32
NAME_POOL_CAPACITY         = 2304
PARAM_META_CAPACITY        = 128

;;; Six bytes per persistent entry, three per current entry, one byte per saved
;;; parameter type, plus the owned-name pool. Keep this literal beside the table
;;; layout so `make nanoc0` can report large reserved workspace separately from
;;; code and small parser/scanner state.
SYMBOL_WORKSPACE_BYTES = 3488

RUNTIME_SYMBOL_COUNT = 5
RUNTIME_NAME_BYTES   = 44
RUNTIME_PARAM_COUNT  = 8

;;; reset_symbol_state
;;; Keep the five fixed runtime function entries and discard every source name,
;;; current-function entry and BSS allocation from the previous translation.
;;; bssBase is supplied by the wrapper/test before parsing begins.
reset_symbol_state:
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
	lda bssBase
	sta bssNextAddress
	lda bssBase+1
	sta bssNextAddress+1
	rts

;;; reserve_persistent_name
;;; Copy currentTokenText into owned storage for persistentCount.
;;; The entry is reserved but not visible until persistentCount is incremented.
;;; Carry clear means symbol or name capacity is exhausted.
reserve_persistent_name:
	ldx persistentCount
	cpx #PERSISTENT_SYMBOL_CAPACITY
	bcc .space
	clc
	rts
.space:
	stx reservedSymbolIndex
	jsr copy_token_to_name_pool
	bcc .full
	ldx reservedSymbolIndex
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

;;; reserve_current_name
;;; Copy currentTokenText for currentCount, but do not make the entry visible.
;;; commit_current_symbol increments currentCount after any initializer has been
;;; checked/compiled.
reserve_current_name:
	ldx currentCount
	cpx #CURRENT_SYMBOL_CAPACITY
	bcc .space
	clc
	rts
.space:
	stx reservedCurrentIndex
	jsr copy_token_to_name_pool
	bcc .full
	ldx reservedCurrentIndex
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
;;; Store [length][currentTokenText...] at namePoolNext.
;;; Carry clear means the bounded pool would overflow.
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
	ldx #$00
.copy:
	cpx currentTokenLength
	beq .done
	iny
	lda currentTokenText,x
	sta (DECL_PTR),y
	inx
	jmp .copy
.done:
	lda nameCopyEnd
	sta namePoolNext
	lda nameCopyEnd+1
	sta namePoolNext+1
	sec
	rts

commit_persistent_symbol:
	inc persistentCount
	rts

commit_current_symbol:
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
;;; X is preserved. Carry set means currentTokenText equals the length-prefixed
;;; pool name at nameCompareOffset.
token_equals_pool_name:
	stx nameCompareSymbolIndex
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
	ldx #$00
.compare:
	cpx currentTokenLength
	beq .equal
	iny
	lda (DECL_PTR),y
	cmp currentTokenText,x
	bne .different
	inx
	jmp .compare
.equal:
	ldx nameCompareSymbolIndex
	sec
	rts
.different:
	ldx nameCompareSymbolIndex
	clc
	rts

;;; allocate_bss
;;; allocSize is a 16-bit byte count.
;;; Carry set: allocOffset is the old BSS offset and allocation is committed.
;;; Carry clear: NC_BSS+allocation would wrap the 16-bit target address space.
;;;
;;; allocOffset is deliberately transient. The declaration emitter sees it while
;;; defining the assembler-visible storage label; later compiler phases refer to
;;; that label by symbol identity and never need to retain the numeric address.
allocate_bss:
	lda bssOffset
	sta allocOffset
	lda bssOffset+1
	sta allocOffset+1

	clc
	lda bssNextAddress
	adc allocSize
	sta allocNextAddress
	lda bssNextAddress+1
	adc allocSize+1
	sta allocNextAddress+1
	bcs .overflow

	clc
	lda bssOffset
	adc allocSize
	sta allocNextOffset
	lda bssOffset+1
	adc allocSize+1
	sta allocNextOffset+1
	bcs .overflow

	lda allocNextAddress
	sta bssNextAddress
	lda allocNextAddress+1
	sta bssNextAddress+1
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
;;; emitted to assembly.
append_parameter_metadata:
	ldx parameterMetaCount
	cpx #PARAM_META_CAPACITY
	bcc .space
	clc
	rts
.space:
	ldy pendingCurrentIndex
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
reservedSymbolIndex:	byte 0
reservedCurrentIndex:	byte 0
pendingCurrentIndex:	byte 0

;;; The large bounded workspace begins here. Everything outside this interval is
;;; executable code or small scalar parser/scanner state.
symbolWorkspaceStart:

;;; Persistent entries. The first five are the fixed runtime functions.
;;; A record is six bytes across parallel arrays:
;;;   name offset (2), kind, type, parameter metadata start, parameter count.
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

;;; Current-function entries. A record is only name offset (2) + type.
;;; Parameter/local role and numeric storage address are facts needed only while
;;; declaring/emitting the slot, not by later source lookup.
currentNameOffsetLo:	ds CURRENT_SYMBOL_CAPACITY
currentNameOffsetHi:	ds CURRENT_SYMBOL_CAPACITY
currentType:		ds CURRENT_SYMBOL_CAPACITY

;;; Persistent call metadata is one byte per parameter: its Phase 1 type.
parameterMetaCount:	byte RUNTIME_PARAM_COUNT
parameterType:
	byte TYPE_CHAR_PTR,TYPE_INT		; io_open(name,length)
	byte TYPE_INT				; io_read(handle)
	byte TYPE_CHAR_PTR,TYPE_INT		; io_create(name,length)
	byte TYPE_INT,TYPE_INT			; io_write(handle,value)
	byte TYPE_INT				; io_close(handle)
	ds PARAM_META_CAPACITY-RUNTIME_PARAM_COUNT

;;; One shared length-prefixed owned-name pool. Runtime names are permanent bytes
;;; at its start; source names follow and current-function names reuse its tail.
persistentNameUsed:	word RUNTIME_NAME_BYTES
namePoolNext:		word RUNTIME_NAME_BYTES
namePool:
	byte 7,'i','o','_','o','p','e','n'
	byte 7,'i','o','_','r','e','a','d'
	byte 9,'i','o','_','c','r','e','a','t','e'
	byte 8,'i','o','_','w','r','i','t','e'
	byte 8,'i','o','_','c','l','o','s','e'
	ds NAME_POOL_CAPACITY-RUNTIME_NAME_BYTES

symbolWorkspaceEnd:

;;; Static BSS allocation state.
bssBase:		word $5000
bssNextAddress:	word $5000
bssOffset:		word 0
zeroRequiredEnd:	word 0
allocSize:		word 0
allocOffset:		word 0
allocNextAddress:	word 0
allocNextOffset:	word 0

;;; Shared symbol scratch.
nameCopyStart:		word 0
nameCopyEnd:		word 0
nameCompareOffset:	word 0
nameCompareSymbolIndex:	byte 0
