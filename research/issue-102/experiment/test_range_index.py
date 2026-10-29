#!/usr/bin/env python3
"""Edge-sensitive index proof, 6502 instruction execution and negative controls."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent/'full_corpus'))
from tape_frontend import TapeBuilder
from range_index import IndexRangeBackend
from execute6502 import relax,CPU

safe='''char slice(char *p, char len) {
  if (len < 2) return 99;
  return p[len-2];
}'''
unsafe='''char slice(char *p, char len) {return p[len-2];}'''
wide='''char slice(char *p, int i) {return p[i];}'''
changed='''char g;
char change();
char slice(char *p, char len) {
  if (g >= 2) {
    change();
    return p[g-2];
  }
  return 99;
}'''

def build(src):
 b=IndexRangeBackend(TapeBuilder(src).build())
 code,_,_=relax(b.run())
 return b,code

checks=0
for src,expect in [(safe,True),(unsafe,False),(wide,False),(changed,False)]:
 b,asm=build(src)
 # Distinguish already-byte indices (ineligible here) from certified -2.
 src_idx=[o for block in b.t.blocks for o in block.ops
          if o.code=='read' and b.defs[o.args[1]].code=='-']
 assert len(src_idx)==(0 if src==wide else 1),src
 if src==wide:
  assert not any(b.y_safe(o) for block in b.t.blocks for o in block.ops if o.code=="read")
 else:
  assert b.y_safe(src_idx[0]) == expect,(src,[(o[1],o[3]) for o in b.range_evidence])
 if not expect:continue
 for length in [0,1,2,3,127,128,254,255]:
  data=bytes((n*7+17)&255 for n in range(256))
  cpu=CPU(asm,data,{'p':0x30ff,'len':length},{},text_base=0x30ff)
  got,_,_=cpu.run(max_steps=10000)
  expected=99 if length<2 else data[length-2]
  assert (got&255)==expected,(length,got,expected)
  checks+=1
# Wide word indexes must address beyond the first 256 bytes, not wrap Y.
b,asm=build(wide)
data=bytes((x*19+13)&255 for x in range(1024))
for i in [0,1,255,256,257,511,767]:
    cpu=CPU(asm,data,{'p':0x30ff,'i':i},{},text_base=0x30ff)
    got,_,_=cpu.run(max_steps=10000)
    assert got&255==data[i],(i,got,data[i]);checks+=1
# The unguarded unsigned-char subtraction is negative at len<2. Its
# low byte would select +254 or +255; a full signed address is required.
b,asm=build(unsafe)
for length in [0,1,2,3,255]:
    cpu=CPU(asm,data,{'p':0x30ff,'len':length},{},text_base=0x30ff)
    cpu.heap[0x30fd]=197;cpu.heap[0x30fe]=199
    got,_,_=cpu.run(max_steps=10000)
    expected={0:197,1:199}.get(length,data[length-2] if length>=2 else 0)
    assert got&255==expected,(length,got,expected);checks+=1
print('PASS',checks,'guarded, page-crossing, genuinely wide, and negative-index 6502 executions; 3 unsafe proof controls')
