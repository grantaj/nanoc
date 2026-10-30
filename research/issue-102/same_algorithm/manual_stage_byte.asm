; Identical C storage and ABI. No persistent cursor: index is ass_image_length.
stage_byte:
__F_stage_byte_entry:
    sta __L_stage_byte_value
    ; C signed int limit: length >= 11264 == $2c00 is rejected.
    lda ass_image_length+1
    bmi __cal_stage_room
    cmp #$2c
    bcs __cal_stage_full
__cal_stage_room:
    clc
    lda ass_image_length
    adc #<ass_image
    sta __ap
    lda ass_image_length+1
    adc #>ass_image
    sta __ap+1
    ldy #$00
    lda __L_stage_byte_value
    sta (__ap),y
    inc ass_image_length
    bne __cal_stage_ret
    inc ass_image_length+1
__cal_stage_ret:
    lda #$00
    rts
__cal_stage_full:
    lda #$0b
    rts
