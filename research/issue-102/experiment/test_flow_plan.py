"""Full 6502 execution oracle for the two-pass fixed-stride table scan.

Checks C-oracle equivalence for real uppercase/lowercase/invalid byte triples,
all 256 possible byte values at each input position, page boundaries, final
candidate and bad lengths. Explicitly tests proof rejection on changed source.
"""
import ctypes
import json
import random
from pathlib import Path

from full_corpus.tape_frontend import TapeBuilder
from full_corpus.flow_plan import FlowPlanBackend, pure_byte_summaries, prove_readonly_arrays
from full_corpus.scratch_allocator import allocate
from full_corpus.execute6502 import CPU

P=Path(__file__).parent
src=P/'full_corpus/whole_corpus/find_mnemonic.c'
t=TapeBuilder(src.read_text()).build()
arrays=json.loads((P/'full_corpus/whole_corpus/arrays.json').read_text())
initialized=json.loads((P/'initialized.json').read_text())
fold=pure_byte_summaries(P/'full_corpus/whole_corpus')
readonly=prove_readonly_arrays(P/'full_corpus/whole_corpus',arrays)
assert 'mnemonic_table' in readonly
b=FlowPlanBackend(t,arrays,initialized,fold,readonly)
assert b.plan and b.plan.stride==3 and b.plan.bound==56,b.plan
asm,meta=allocate(t,b,b.run())
assert meta['instruction_bytes']==68,meta
assert b.decisions=={'planned_fixed_stride_table_scan':1}

class IndexedCPU(CPU):
    def rd(self,arg):
        if arg.endswith(',x') and not arg.startswith('('):
            name=arg[:-2]
            return self.heap.get((self.bases[name]+self.X)&65535,0)
        return super().rd(arg)

lib=ctypes.CDLL(str(P/'full_corpus/host_ass.so'))
lib.find_mnemonic.argtypes=[ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ubyte]
lib.find_mnemonic.restype=ctypes.c_int
names=bytes(initialized['mnemonic_table'][:168])
assert len(names)==168 and all(65<=x<=90 for x in names)
entries=[names[i*3:i*3+3] for i in range(56)]
checks=0

def test_case(data,length,ptr_base=0x41ff,table_base=0x50ff):
    global checks
    assert len(data)==3,(data,length)
    inp=(ctypes.c_ubyte*3)(*data)
    want=lib.find_mnemonic(inp,length)
    cpu=IndexedCPU(asm,b'',{'name':ptr_base,'length':length},{})
    cpu.bases['mnemonic_table']=table_base
    cpu.heap.update({(table_base+i)&65535:x for i,x in enumerate(initialized['mnemonic_table'])})
    cpu.heap.update({(ptr_base+i)&65535:x for i,x in enumerate(data)})
    got,_,_=cpu.run(max_steps=12000)
    want &= 65535
    assert got==want,(data,length,hex(ptr_base),hex(table_base),got,want)
    checks+=1

for i,name in enumerate(entries):
    assert all(65<=x<=90 for x in name)
    test_case(name,3)
    test_case(name.lower(),3)
    test_case(bytes(x|32 if j%2==0 else x for j,x in enumerate(name)),3)
    if i in (0,1,10,40,55):
        for addr in (0x4080,0x40fe,0x41ff,0x6200):
            test_case(name,3,addr,0x50ff)
            test_case(name.lower(),3,addr,0x60fe)

for pos in range(3):
    for v in range(256):
        name=bytearray(entries[37]);name[pos]=v
        test_case(bytes(name),3)

rng=random.Random(3318)
for i in range(160):
    data=bytes(rng.randrange(256) for _ in range(3))
    test_case(data,3)
for length in (0,1,2,4,254,255):
    for word in entries[::7]+[b'???',b'0A\x00',b'\xff\xff\xff']:
        test_case(word,length)

# Non-constant or non-upper-case table must fail the proof (not emit a plan).
modified=dict(initialized);modified['mnemonic_table']=list(initialized['mnemonic_table'])
modified['mnemonic_table'][40]=ord('a')
assert FlowPlanBackend(TapeBuilder(src.read_text()).build(),arrays,modified,fold,readonly).plan is None
# Modified callee byte semantics must fail the exhaustive equivalence proof.
invalid=dict(fold);invalid['upper_char']=tuple(range(256))
assert FlowPlanBackend(TapeBuilder(src.read_text()).build(),arrays,initialized,invalid,readonly).plan is None
# Modified loop bound invalidates structural proof / 6502 X range.
changed=src.read_text().replace('candidate < 56','candidate < 87')
assert FlowPlanBackend(TapeBuilder(changed).build(),arrays,initialized,fold,readonly).plan is None
print('PASS',checks,'standalone physically executed machine lookup cases;',
      '3 explicit negative-proof controls; 68-byte function')
