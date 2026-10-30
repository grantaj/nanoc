"""Adversarial signed/unsigned width tests for generic compare lowering."""
from full_corpus.byte_demand import ByteDemandBackend
from full_corpus.tape_frontend import TapeBuilder
from full_corpus.execute6502 import CPU,relax
import random,operator
random.seed(3321)
cases=0
for typ in ('int','unsigned'):
 for cmp in ('<','<=','>','>='):
  for rhs in ('b','0','127','255','256','32767','32768','65535'):
   if typ=='int' and rhs in ('32768','65535'):continue
   src=f'char test({typ} a, {typ} b) {{ if (a {cmp} {rhs}) return 1; return 0; }}'
   asm,_,_=relax(ByteDemandBackend(TapeBuilder(src).build()).run())
   rel={'<':operator.lt,'<=':operator.le,'>':operator.gt,'>=':operator.ge}[cmp]
   for _ in range(100):
    x=random.choice([0,1,127,128,255,256,32767,32768,65535,random.randrange(65536)])
    y=random.choice([0,1,127,128,255,256,32767,32768,65535,random.randrange(65536)])
    rr=int(rhs) if rhs!='b' else y
    xx=x if typ=='unsigned' or x<32768 else x-65536
    yy=rr if typ=='unsigned' or rr<32768 else rr-65536
    expected=int(rel(xx,yy))
    actual,_,_=CPU(asm,[],{'a':x,'b':y},{}).run(max_steps=4000)
    assert actual==expected,(src,x,y,actual,expected)
    cases+=1
print('PASS',cases,'signed/unsigned word comparisons')
