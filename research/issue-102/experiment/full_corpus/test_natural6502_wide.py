"""Direct interpreted-6502 checks of word/ptr/call conventions."""
import json,random
from functools import lru_cache
from pathlib import Path
from natural6502_wide import Natural6502Wide,Unsupported
from execute6502 import CPU,relax

D=Path(__file__).parent/'whole_corpus'
arrays=json.loads((D/'arrays.json').read_text())
@lru_cache(None)
def code(fn):return Natural6502Wide((D/(fn+'.c')).read_text(),arrays).run()
def state(fn,**kw):return {'__L_'+fn+'_'+k:v for k,v in kw.items()}
def run(fn,mem,src=(),calls=None,base=0x30ef):
    cpu=CPU(code(fn),list(src),mem,calls or {},text_base=base)
    cpu.trace=[]
    v,m,_=cpu.run(max_steps=20000)
    return v,m
rng=random.Random(1026502)
checks=0
# Signed 16-bit return and real pointer indexed at zero.
for b in [0,1,2,127,255]:
    for scope in (0,1,17,255):
        for c in (ord('.'),ord('x')):
            mem=state('scope_for_name',name=0x30ef,length=b);mem['current_scope']=scope
            expected= -1 if b==0 or (c==ord('.') and scope==0) else scope if c==ord('.') else 0
            v,_=run('scope_for_name',mem,[c],base=0x30ef)
            assert v==expected&65535,(b,scope,c,v,expected)
            checks+=1
# Word arithmetic/subtraction, wraparound and unsigned comparisons.
values=[0,1,2,127,128,129,254,255,256,257,32767,32768,65534,65535]
for _ in range(70):values.append(rng.randrange(65536))
for a in values:
    for b in [0,1,127,128,255,256,32767,32768,65535]:
        delta=(a-b)&65535
        expected=delta if delta<=127 else (delta & 255) if delta>=65408 else 65535
        v,_=run('relative_byte',state('relative_byte',target=a,base=b))
        assert v==expected,(a,b,v,expected)
        checks+=1
# 16-bit -> byte, byte values and prefix selection (prefix argument).
for v in values:
    for p in [0,1,2,255]:
        expected=v&255 if p==1 else (v>>8)&255
        x,_=run('apply_byte_prefix',dict(state('apply_byte_prefix',value=v,prefix=p),VALUE_PREFIX_LOW=1))
        assert (x&255)==expected,(v,p,x,expected)
        checks+=1
# Calls and char promotion to 16-bit, including all inputs and -1 sentinel.
for c in range(256):
    def upper_char(k):return k-32 if 97<=k<=122 else k
    u=upper_char(c)
    expected=u-48 if 48<=u<=57 else u-65+10 if 65<=u<=70 else -1
    x,_=run('hex_nibble',state('hex_nibble',c=c),calls={'upper_char':upper_char})
    assert x==expected&65535,(c,x,expected)
    checks+=1
print('PASS',checks,'direct interpreter word/pointer/call cases')
