"""Adversarial register-as-physical-home cases: positive and must-refuse."""
from register_home import candidate_plan

def check(case,asm,wanted):
 r=candidate_plan(asm,'f','__L_f_v','x','u8')
 assert (r is not None)==wanted,(case,r)
 if r:
  text='\n'.join(r[0]); assert 'tax' in text and 'txa' in text
 print('PASS',case,'accepted' if wanted else 'refused')

check('straight-line byte local', ['f:','    lda #$07','    sta __L_f_v','    lda __L_f_v','    rts'],True)
check('call clobbers X', ['f:','    lda #$07','    sta __L_f_v','    jsr g','    lda __L_f_v','    rts'],False)
check('counter live in X at store', ['f:','    ldx #$03','    lda #$07','    sta __L_f_v','    stx other','    lda __L_f_v','    rts'],False)
check('alternate entry without definition', ['f:','    bne .yes','.no:','    lda #$07','    sta __L_f_v','.yes:','    lda __L_f_v','    rts'],False)
check('flag-sensitive store after comparison', ['f:','    lda #$07','    cmp #$06','    sta __L_f_v','    lda __L_f_v','    rts'],False)
check('register clobbered before read', ['f:','    lda #$07','    sta __L_f_v','    ldx #$00','    lda __L_f_v','    rts'],False)
