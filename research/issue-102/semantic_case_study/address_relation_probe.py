"""Diagnostic, non-production: test two equivalent 6502 field-address strategies.
Uses actual linker addresses from the recovered #102 assembler and exhaustive
0..639 indexes. This tests cost and machine semantics of the ADDRESS FRAGMENT
only, not an entire C function or complete executable.
"""
import json, pathlib, random, re, sys, os
ROOT=pathlib.Path(os.environ.get('SEMANTIC_CASE_ROOT', pathlib.Path(__file__).parent))/'nanoc_machine_value_home_planner'
sym=json.loads((ROOT/'symbols.json').read_text())
FIELDS=('fixup_stage','fixup_symbol','fixup_addend')
BASES=[sym[k] for k in FIELDS]
assert all(b&255==0x94 for b in BASES)
assert [BASES[k+1]-BASES[k] for k in range(2)]==[0x500,0x500]
ZP={'__ix':0x10, '__ix+1':0x11,'__ap':0x12,'__ap+1':0x13}
OUTPUT={'out0':0x3000,'out0+1':0x3001,'out1':0x3002,'out1+1':0x3003,'out2':0x3004,'out2+1':0x3005}
LOC={'i':0x3010,'i+1':0x3011, **ZP,**OUTPUT}

def build_independent():
 lines=[]
 for k,base in enumerate(BASES):
  lines += [
  'lda i','asl','sta __ix', 'lda i+1','rol','sta __ix+1',
  'clc','lda __ix',f'adc #${base&255:02x}','sta __ap',
  'lda __ix+1',f'adc #${base>>8:02x}','sta __ap+1',
  'ldy #$00','lda (__ap),y',f'sta out{k}',
  'iny','lda (__ap),y',f'sta out{k}+1']
 return lines

def build_related():
 base=BASES[0]
 lines=[
  'lda i','asl','sta __ix', 'lda i+1','rol','sta __ix+1',
  'clc','lda __ix',f'adc #${base&255:02x}','sta __ap',
  'lda __ix+1',f'adc #${base>>8:02x}','sta __ap+1']
 for k in range(3):
  if k:
   step=(BASES[k]-BASES[k-1])>>8
   lines+=['clc','lda __ap+1',f'adc #${step:02x}','sta __ap+1']
  lines+=['ldy #$00','lda (__ap),y',f'sta out{k}',
           'iny','lda (__ap),y',f'sta out{k}+1']
 return lines

def ins_size(line):
 op,*rest=line.split(' ',1);a=rest[0] if rest else ''
 if not a:return 1
 if a.startswith('#') or a.startswith('(') or a in ZP:return 2
 return 3

class Machine:
 def __init__(self,idx,values):
  self.mem=bytearray(65536)
  self.mem[LOC['i']]=idx&255;self.mem[LOC['i+1']]=idx>>8
  for k,base in enumerate(BASES):
   self.mem[base+2*idx]=values[2*k]
   self.mem[base+2*idx+1]=values[2*k+1]
  self.a=self.y=self.c=0
 def value(self,a):
  if a.startswith('#$'):return int(a[2:],16)
  if a=='(__ap),y':
   p=self.mem[LOC['__ap']]+256*self.mem[LOC['__ap+1']]
   return self.mem[(p+self.y)&65535]
  return self.mem[LOC[a]]
 def write(self,a,v):self.mem[LOC[a]]=v&255
 def run(self,lines):
  for ln in lines:
   p=ln.split(' ',1);o=p[0];arg=p[1] if len(p)>1 else ''
   if o=='lda':self.a=self.value(arg)
   elif o=='sta':self.write(arg,self.a)
   elif o=='ldy':self.y=self.value(arg)
   elif o=='iny':self.y=(self.y+1)&255
   elif o=='clc':self.c=0
   elif o=='asl':self.c=(self.a>>7)&1;self.a=(self.a<<1)&255
   elif o=='rol':
    v=(self.a if not arg else self.value(arg));carry=v>>7
    rotated=((v<<1)|self.c)&255
    if arg:self.write(arg,rotated)
    else:self.a=rotated
    self.c=carry
   elif o=='adc':
    n=self.a+self.value(arg)+self.c
    self.a=n&255;self.c=(n>>8)&1
   else:raise ValueError(ln)
  return [self.mem[OUTPUT[f'out{k}']]+256*self.mem[OUTPUT[f'out{k}+1']] for k in range(3)]

if __name__=='__main__':
 original=build_independent();related=build_related()
 rand=random.Random(20261030)
 tests=0
 for i in range(640):
  for j in range(3):
   data=tuple(rand.randrange(256) for _ in range(6))
   wanted=[data[0]+256*data[1],data[2]+256*data[3],data[4]+256*data[5]]
   for code in (original,related):
    got=Machine(i,data).run(code)
    assert got==wanted,(i,j,got,wanted)
   tests+=1
 sizes=[sum(ins_size(t) for t in code) for code in [original,related]]
 print(json.dumps({'addresses':{k:f'${sym[k]:04x}' for k in FIELDS},
  'tests_per_strategy':tests,
  'independent_instructions':len(original),'independent_bytes':sizes[0],
  'shared_offset_instructions':len(related),'shared_offset_bytes':sizes[1],
  'savings_in_fragment_before_outlining':sizes[0]-sizes[1]},indent=2))
 (pathlib.Path(__file__).parent/'address_relation_sequences.txt').write_text(
  'INDEPENDENT ADDRESS COMPUTATIONS:\n'+'\n'.join(original)+'\n\n'+
  'SHARED AFFINE OFFSET, PAGE RETARGETING:\n'+'\n'.join(related)+'\n')
