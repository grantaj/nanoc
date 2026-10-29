"""Independent exhaustive 6502 arithmetic test for the word RMW choice.
Both wraps are required: signed/unsigned arithmetic is modulo $10000.
"""
from full_corpus.execute6502 import CPU
from random import Random
r=Random(102)
xs=list(range(0,512))+[0x7fff,0x8000,0xff00,0xfffe,0xffff]+[r.randrange(65536) for _ in range(1500)]
count=0
for name,inst,src in [
 ('increment','inc','entry:\n    inc x\n    bne done\n    inc x+1\ndone:\n    rts\n'),
 ('decrement','dec','entry:\n    lda x\n    bne keep_high\n    dec x+1\nkeep_high:\n    dec x\n    rts\n')]:
 for x in xs:
  c=CPU(src,[],{'x':x},{})
  _,m,_=c.run(20)
  got=m.get('x',0)|m.get('x+1',0)<<8
  expected=(x+(1 if name=='increment' else -1))&65535
  assert got==expected,(name,x,got,expected)
  count+=1
print('PASS',count,'16-bit increment/decrement machine executions including wrap/sign edges')
