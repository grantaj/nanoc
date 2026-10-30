; Hand-coded control: EXACT SAME C ARRAYS and CALL ABI, unlike ass/symbols.asm.
; i: __L_find_symbol_i (u16); wanted_scope: __L_find_symbol_wanted_scope (u16).
; __ap and __ix are two existing ZP pointer pairs; __tmp0..3 existing scratch.
; No special native-assembler symbol-record representation used.
find_symbol:
__F_find_symbol_entry:
    sta __L_find_symbol_length
    lda __L_find_symbol_name
    sta __call_scope_for_name_0
    lda __L_find_symbol_name+1
    sta __call_scope_for_name_0+1
    lda __L_find_symbol_length
    jsr scope_for_name
    sta __L_find_symbol_wanted_scope
    txa
    bpl __cal_scope_ok
    jmp __cal_invalid
__cal_scope_ok:
    lda #$00
    sta __L_find_symbol_i
    sta __L_find_symbol_i+1
    lda #<symbol_scope
    sta __ap
    lda #>symbol_scope
    sta __ap+1
    lda #<symbol_name_length
    sta __ix
    lda #>symbol_name_length
    sta __ix+1
__cal_loop:
    lda __L_find_symbol_i+1
    cmp symbol_count+1
    bcc __cal_entry
    beq __cal_check_low
    jmp __cal_notfound
__cal_check_low:
    lda __L_find_symbol_i
    cmp symbol_count
    bcc __cal_entry
    jmp __cal_notfound
__cal_entry:
    ldy #$00
    lda (__ap),y
    cmp __L_find_symbol_wanted_scope
    beq __cal_len_match
    jmp __cal_advance
__cal_len_match:
    lda (__ix),y
    cmp __L_find_symbol_length
    beq __cal_save
    jmp __cal_advance
__cal_save:
    ; Save the two outer table cursors while using them for name comparison.
    lda __ap
    sta __tmp2
    lda __ap+1
    sta __tmp3
    lda __ix
    sta __L_find_symbol_offset
    lda __ix+1
    sta __L_find_symbol_offset+1
    ; Offset entry is symbol_name_offset[2*i].
    lda __L_find_symbol_i
    asl
    sta __tmp0
    lda __L_find_symbol_i+1
    rol
    ; Add base to the two-byte index without a word-sized temporary.
    adc #>symbol_name_offset
    sta __ap+1
    lda __tmp0
    clc
    adc #<symbol_name_offset
    sta __ap
    bcc __cal_addr_ready
    inc __ap+1
__cal_addr_ready:
    ldy #$00
    lda (__ap),y
    sta __tmp0
    iny
    lda (__ap),y
    sta __tmp1
    ; __ap = symbol_name_bytes + stored offset
    lda __tmp0
    clc
    adc #<symbol_name_bytes
    sta __ap
    lda __tmp1
    adc #>symbol_name_bytes
    sta __ap+1
    lda __L_find_symbol_name
    sta __ix
    lda __L_find_symbol_name+1
    sta __ix+1
    ldy #$00
__cal_compare:
    cpy __L_find_symbol_length
    bcs __cal_found
    lda (__ap),y
    cmp (__ix),y
    bne __cal_mismatch
    iny
    bne __cal_compare
__cal_mismatch:
    lda __tmp2
    sta __ap
    lda __tmp3
    sta __ap+1
    lda __L_find_symbol_offset
    sta __ix
    lda __L_find_symbol_offset+1
    sta __ix+1
__cal_advance:
    inc __ap
    bne __cal_next_scope
    inc __ap+1
__cal_next_scope:
    inc __ix
    bne __cal_next_len
    inc __ix+1
__cal_next_len:
    inc __L_find_symbol_i
    bne __cal_next_i
    inc __L_find_symbol_i+1
__cal_next_i:
    jmp __cal_loop
__cal_found:
    lda __L_find_symbol_i
    ldx __L_find_symbol_i+1
    rts
__cal_invalid:
    lda #$fe
    ldx #$ff
    rts
__cal_notfound:
    lda #$ff
    tax
    rts
