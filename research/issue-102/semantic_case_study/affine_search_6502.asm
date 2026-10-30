; Cost-optimal under the stated address recipes, independent loads only
lda i
asl
sta __ix
lda i+1
rol
sta __ix+1
clc
lda __ix
adc #$94
sta __ap
lda __ix+1
adc #$b5
sta __ap+1
ldy #$00
lda (__ap),y
sta out0
iny
lda (__ap),y
sta out0+1
clc
lda __ap+1
adc #$05
sta __ap+1
ldy #$00
lda (__ap),y
sta out1
iny
lda (__ap),y
sta out1+1
clc
lda __ap+1
adc #$05
sta __ap+1
ldy #$00
lda (__ap),y
sta out2
iny
lda (__ap),y
sta out2+1
