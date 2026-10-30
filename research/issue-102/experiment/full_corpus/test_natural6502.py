"""Independent interpreted 6502 differential checks of the new *emitted code*.
No reliance on the global assembler's normal smoke-test input distribution.
"""
from pathlib import Path
from natural6502 import Natural6502, Unsupported
from execute6502 import CPU
import random, json
class NoTrace:
    def append(self,value):pass

P=Path(__file__).parent
arrays=json.loads((P/'whole_corpus'/'arrays.json').read_text())

def get(fn):
    return Natural6502((P/'whole_corpus'/(fn+'.c')).read_text(),arrays).run()

def run_byte(fn, inp, extra=None):
    state={'__L_'+fn+'_'+('index' if fn.endswith('mode_for_index') else 'c'):inp}
    if extra:state.update(extra)
    return CPU(get(fn),[],state,{}).run()[0]&255

checks=0
for v in range(256):
    expected=v-32 if ord('a')<=v<=ord('z') else v
    assert run_byte('upper_char',v)==expected,(v,run_byte('upper_char',v),expected)
    checks+=1
for fn,vals in [('short_mode_for_index',(23,31,37)),('long_mode_for_index',(41,43,47))]:
    names=('MODE_ZERO_PAGE_X','MODE_ZERO_PAGE_Y','MODE_ZERO_PAGE') if fn.startswith('short') else ('MODE_ABSOLUTE_X','MODE_ABSOLUTE_Y','MODE_ABSOLUTE')
    md=dict(zip(names,vals))
    for i in range(256):
        expect=vals[0] if i==1 else vals[1] if i==2 else vals[2]
        got=run_byte(fn,i,md)
        assert got==expect,(fn,i,got,expect)
        checks+=1

rng=random.Random(6502)
case_lengths=[0,1,2,3,16,127,128,129,253,254,255]
examples=[]
for m in case_lengths:
    for n in case_lengths:
        for equal in (True,False):
            a=[rng.randrange(256) for _ in range(m)]
            b=a[:n]+[rng.randrange(256) for _ in range(max(0,n-len(a)))]
            if not equal and m and n and m==n:
                at=rng.randrange(n);b[at]^=1
            examples.append((a,b))
for _ in range(1200):
    n=rng.randrange(256);m=rng.randrange(256) if rng.randrange(4)==0 else n
    a=[rng.randrange(256) for _ in range(m)]
    b=a[:n]+[rng.randrange(256) for _ in range(max(0,n-len(a)))]
    if m==n and n and rng.randrange(3)==0:b[rng.randrange(n)]^=rng.randrange(1,256)
    examples.append((a,b))
code=get('same_text')
for ai,bi in [(0x30ff,0x41fe),(0x30f0,0x41f1),(0x3030,0x5030)]:
    for a,b in examples:
        expect=int(len(a)==len(b) and a==b)
        globals_={
            '__L_same_text_a':ai,
            '__L_same_text_b':bi,
            '__L_same_text_a_length':len(a),
            '__L_same_text_b_length':len(b),
        }
        cpu=CPU(code,[],globals_,{})
        cpu.trace=NoTrace()
        cpu.heap.update({ai+i:v for i,v in enumerate(a)})
        cpu.heap.update({bi+i:v for i,v in enumerate(b)})
        got=cpu.run(max_steps=100000)[0]&255
        assert got==expect,('same_text',hex(ai),hex(bi),len(a),len(b),got,expect)
        checks+=1
print('PASS',checks,'machine-executed natural 6502 cases across four C routines')
