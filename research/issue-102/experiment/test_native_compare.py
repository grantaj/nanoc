#!/usr/bin/env python3
"""Independent 6502 semantic tests of all immediate signed/unsigned word compares."""
from types import SimpleNamespace
from random import Random
from full_corpus.tape_frontend import Op
from full_corpus.execute6502 import CPU
from full_corpus.compare_native import NativeCompareBackend
R=Random(0x6502)
bounds=[-32768,-1025,-256,-129,-128,-2,-1,0,1,2,7,127,128,255,256,511,32767,32768,65535]
xs=[0,1,2,127,128,255,256,257,32767,32768,32769,65280,65534,65535]
conds=['<','<=','>','>=','==','!=']
def signed(x):return x-65536 if x>=32768 else x
pass_count=0
for unsigned in [False,True]:
 for left_constant in [False,True]:
  for cond in conds:
   for bound in bounds:
    tape=SimpleNamespace(values={1:'u16' if unsigned else 's16',2:'u16' if unsigned else 's16'})
    fake=object.__new__(NativeCompareBackend)
    fake.t=tape
    fake._probe=True;fake.labels=0;fake.a_known=set();fake.direct_comparisons={}
    fake.native_cmp_count=fake.native_sign_count=fake.native_zero_count=0
    fake.defs={1:Op('load',('x',),'u16' if unsigned else 's16',1), 2:Op('const',(bound,),'u16' if unsigned else 's16',2)}
    lines=[]
    fake.emit=lambda op,arg=None:lines.append('    '+op+(' '+arg if arg is not None else ''))
    fake.val=lambda v,high=False: ('x+1' if high else 'x') if v==1 else '#$%02x'%(((bound&65535)>>(8 if high else 0))&255)
    args=(2,1) if left_constant else (1,2)
    comp=SimpleNamespace(code=cond,args=args,result=3)
    fake.compare(comp,'yes','no')
    asm='entry:\n'+'\n'.join(lines)+'\nyes:\n    lda #$01\n    rts\nno:\n    lda #$00\n    rts\n'
    sample=xs+[R.randrange(65536) for _ in range(6)]
    for x in sample:
     a=signed(bound&65535) if left_constant and not unsigned else (bound&65535) if left_constant else signed(x) if not unsigned else x
     b=signed(x) if left_constant and not unsigned else x if left_constant else signed(bound&65535) if not unsigned else bound&65535
     expected=int({'<':lambda:a<b,'<=':lambda:a<=b,'>':lambda:a>b,'>=':lambda:a>=b,'==':lambda:a==b,'!=':lambda:a!=b}[cond]())
     try:actual=CPU(asm,[],{'x':x},{ }).run(70)[0]&255
     except Exception as e:raise AssertionError((unsigned,left_constant,cond,bound,x,asm,e))
     if actual!=expected:raise AssertionError((unsigned,left_constant,cond,bound,x,expected,actual,asm))
     pass_count+=1
print('PASS',pass_count,'signed/unsigned/commuted 6502 comparison executions; both sign boundaries and >16-bit cases')
