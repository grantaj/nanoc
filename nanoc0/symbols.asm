;;; symbols.asm
;;;
;;; Nano C Phase 1 symbol and static-storage state.
;;;
;;; There are only two symbol areas:
;;;   - persistent globals and already-defined functions;
;;;   - parameters/locals for the function currently being compiled.
;;;
;;; Both are linear bounded arrays.  Names live in one owned byte pool.  The
;;; current function allocates names after persistentNameUsed; ending a function
;;; simply resets namePoolNext to persistentNameUsed and reuses those bytes.
;;;
;;; lookup_symbol always checks current-function names first, so a local or
;;; parameter may shadow a global.  No other scope machinery exists.

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

CURRENT_PARAMETER = 1
CURRENT_LOCAL     = 2

SYMBOL_AREA_NONE       = 0
SYMBOL_AREA_CURRENT    = 1
SYMBOL_AREA_PERSISTENT = 2

PERSISTENT_SYMBOL_CAPACITY = 128
CURRENT_SYMBOL_CAPACITY    = 64
NAME_POOL_CAPACITY         = 2048
PARAM_META_CAPACITY        = 192

RUNTIME_SYMBOL_COUNT = 5
RUNTIME_NAME_BYTES   = 39
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
	lda currentTokenLength
	sta persistentNameLength,x
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
	lda currentTokenLength
	sta currentNameLength,x
	sec
	rts
.full:
	clc
	rts

;;; copy_token_to_name_pool
;;; Copy the reusable token text into the next owned-name bytes.
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
	lda currentNameLength,x
	cmp currentTokenLength
	bne .next
	lda currentNameOffsetLo,x
	sta nameCompareOffset
	lda currentNameOffsetHi,x
	sta nameCompareOffset+1
	jsr token_equals_pool_name
	bcs .found
.next:
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
	lda persistentNameLength,x
	cmp currentTokenLength
	bne .next
	lda persistentNameOffsetLo,x
	sta nameCompareOffset
	lda persistentNameOffsetHi,x
	sta nameCompareOffset+1
	jsr token_equals_pool_name
	bcs .found
.next:
	inx
	jmp .loop
.found:
	sec
	rts
.missing:
	clc
	rts

;;; token_equals_pool_name
;;; X is preserved.  Carry set means currentTokenText equals the pool name at
;;; nameCompareOffset.  Length equality has already been checked by the caller.
token_equals_pool_name:
	clc
	lda #<namePool
	adc nameCompareOffset
	sta DECL_PTR
	lda #>namePool
	adc nameCompareOffset+1
	sta DECL_PTR+1
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
;;; Carry clear: NC_BSS+allocation would wrap the 16-bit target address space.
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
;;; A=TYPE_*.  allocSize receives the exact target width.
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
;;; pendingCurrentIndex identifies a committed parameter symbol.
;;; Carry clear means the bounded parameter metadata area is full.
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
	lda currentStorageOffsetLo,y
	sta parameterStorageOffsetLo,x
	lda currentStorageOffsetHi,y
	sta parameterStorageOffsetHi,x
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

;;; Persistent entries.  The first five are the fixed runtime functions.
persistentNameOffsetLo:
	byte 0,7,14,23,31
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentNameOffsetHi:
	byte 0,0,0,0,0
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentNameLength:
	byte 7,7,9,8,8
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentKind:
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
	byte SYMBOL_RUNTIME_FUNCTION,SYMBOL_RUNTIME_FUNCTION
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentType:
	byte TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT,TYPE_INT
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentStorageOffsetLo:
	ds PERSISTENT_SYMBOL_CAPACITY
persistentStorageOffsetHi:
	ds PERSISTENT_SYMBOL_CAPACITY
persistentArrayLengthLo:
	ds PERSISTENT_SYMBOL_CAPACITY
persistentArrayLengthHi:
	ds PERSISTENT_SYMBOL_CAPACITY
persistentParamStart:
	byte 0,2,3,5,7
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT
persistentParamCount:
	byte 2,1,2,2,1
	ds PERSISTENT_SYMBOL_CAPACITY-RUNTIME_SYMBOL_COUNT

;;; Current-function entries.  Old bytes are ignored after currentCount resets.
currentNameOffsetLo:	ds CURRENT_SYMBOL_CAPACITY
currentNameOffsetHi:	ds CURRENT_SYMBOL_CAPACITY
currentNameLength:	ds CURRENT_SYMBOL_CAPACITY
currentKind:		ds CURRENT_SYMBOL_CAPACITY
currentType:		ds CURRENT_SYMBOL_CAPACITY
currentStorageOffsetLo:	ds CURRENT_SYMBOL_CAPACITY
currentStorageOffsetHi:	ds CURRENT_SYMBOL_CAPACITY

;;; Persistent call metadata.  Runtime functions occupy the first eight slots;
;;; their storage offset is $ffff because #57 supplies their concrete runtime
;;; boundary rather than allocating source-level BSS slots here.
parameterMetaCount:	byte RUNTIME_PARAM_COUNT
parameterType:
	byte TYPE_CHAR_PTR,TYPE_INT		; io_open(name,length)
	byte TYPE_INT				; io_read(handle)
	byte TYPE_CHAR_PTR,TYPE_INT		; io_create(name,length)
	byte TYPE_INT,TYPE_INT			; io_write(handle,value)
	byte TYPE_INT				; io_close(handle)
	ds PARAM_META_CAPACITY-RUNTIME_PARAM_COUNT
parameterStorageOffsetLo:
	byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
	ds PARAM_META_CAPACITY-RUNTIME_PARAM_COUNT
parameterStorageOffsetHi:
	byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
	ds PARAM_META_CAPACITY-RUNTIME_PARAM_COUNT

;;; One shared owned-name pool.  Runtime names are permanent bytes at its start.
persistentNameUsed:	word RUNTIME_NAME_BYTES
namePoolNext:		word RUNTIME_NAME_BYTES
namePool:
	byte 'i','o','_','o','p','e','n'
	byte 'i','o','_','r','e','a','d'
	byte 'i','o','_','c','r','e','a','t','e'
	byte 'i','o','_','w','r','i','t','e'
	byte 'i','o','_','c','l','o','s','e'
	ds NAME_POOL_CAPACITY-RUNTIME_NAME_BYTES

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
