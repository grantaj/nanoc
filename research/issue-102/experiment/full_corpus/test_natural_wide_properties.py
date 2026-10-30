"""Machine execution for generic 16-bit operations and pointer indexed access."""
import random
from natural6502_wide import Natural6502Wide
from execute6502 import CPU
from functools import lru_cache
rng=random.Random(6502102)
values=[0,1,2,7,127,128,129,254,255,256,257,511,512,32767,32768,32769,65533,65534,65535]+[rng.randrange(65536) for _ in range(70)]
@lru_cache(None)
def emit(src):return Natural6502Wide(src).run()
checks=0
for t in ('int','unsigned'):
 for op in ('==','!=','<','<=','>','>='):
  src=f'char compare({t} a, {t} b) {{ if (a {op} b) return 1; return 0; }}'
  code=emit(src)
  for a in values:
   for b in (0,1,127,128,255,256,257,32767,32768,65534,65535):
    aa=a if t=='unsigned' or a<32768 else a-65536
    bb=b if t=='unsigned' or b<32768 else b-65536
    expected=int(eval(f'{aa} {op} {bb}'))
    cpu=CPU(code,[],{'__L_compare_a':a,'__L_compare_b':b},{})
    actual=cpu.run(max_steps=200)[0]&255
    assert actual==expected,(t,op,a,b,actual,expected)
    checks+=1
for op in ('+','-','&','|','^'):
 src=f'unsigned compute(unsigned a, unsigned b) {{return a {op} b;}}'
 code=emit(src)
 for a in values:
  for b in (0,1,127,128,255,256,511,32767,32768,65535):
   expect=eval(f'{a} {op} {b}')&65535
   got=CPU(code,[],{'__L_compute_a':a,'__L_compute_b':b},{}).run(max_steps=200)[0]
   assert got==expect,(op,a,b,got,expect)
   checks+=1
for source in ('char get(char *p, int i){ return p[i]; }',
               'char put(char *p, int i, char v){ p[i] = v; return v; }'):
 f='put' if 'put(' in source else 'get'
 code=emit(source)
 for a in (0,1,254,255,256,257,510,511,767,1023):
  for base in (0x30f0,0x3100,0x3ffe):
   data=[rng.randrange(256) for _ in range(a+1)]
   initial={'__L_'+f+'_p':base,'__L_'+f+'_i':a}
   if f=='put':initial['__L_put_v']=143
   cpu=CPU(code,data,initial,{},text_base=base)
   got=cpu.run(max_steps=300)[0]&255
   if f=='get':assert got==data[a],(f,a,base,got,data[a])
   else:assert got==143 and cpu.heap[(base+a)&65535]==143,(f,a,base,got)
   checks+=1
print('PASS',checks,'native machine word comparison/arithmetic/indexed read-write executions')
