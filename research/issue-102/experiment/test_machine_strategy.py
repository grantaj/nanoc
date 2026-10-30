"""Machine-executed tests for independently planned 6502 recipes.

The 76 scan tests verify signed-zero/negative bounds, >255 traversals,
explicit first/middle/last failure and page crossings. The 256 byte tests
verify C's unsigned-char upper-case semantics; only the loops are currently
chosen by the whole-image size selector.
"""
from pathlib import Path
import json
from full_corpus.tape_frontend import TapeBuilder
from full_corpus.machine_strategy import MachineStrategyBackend
from full_corpus.scratch_allocator import allocate
from full_corpus.execute6502 import CPU
P=Path(__file__).parent
arrays=json.loads((P/'full_corpus/whole_corpus/arrays.json').read_text())
checks=0
for fn,table,bound,marker,match in [
    ('all_fixups_resolved','fixup_kind','fixup_count','FIXUP_NONE','!='),
    ('all_symbols_defined','symbol_kind','symbol_count','SYMBOL_LABEL_UNDEFINED','==')]:
    t=TapeBuilder((P/'full_corpus/whole_corpus'/(fn+'.c')).read_text()).build()
    b=MachineStrategyBackend(t,arrays)
    asm,info=allocate(t,b,b.run())
    assert b.scan_plan and info['instruction_bytes']==69,(fn,info)
    base=0x5ff0 if table=='fixup_kind' else 0x40f0
    for n in (-1,0,1,2,15,16,255,256,257,511,640 if table=='fixup_kind' else 896):
        for at in ([-1] if n<=0 else [-1,0,n//2,n-1]):
            marker_value=0 if match=='!=' else 1
            default=marker_value if match=='!=' else 0
            opposite=1-marker_value if match=='!=' else marker_value
            data=[default]*max(0,n)
            if at>=0:data[at]=opposite
            cpu=CPU(asm,b'',{bound:n&65535,marker:marker_value},{})
            cpu.bases[table]=base
            cpu.heap.update({(base+i)&65535:x for i,x in enumerate(data)})
            got,_,_=cpu.run(max_steps=10000)
            want=0 if n>0 and at>=0 else 1
            assert (got&255)==want,(fn,n,at,got,want)
            checks+=1
print('PASS',checks,'machine cursor scans')

t=TapeBuilder((P/'full_corpus/whole_corpus/upper_char.c').read_text()).build()
b=MachineStrategyBackend(t,arrays)
asm,info=allocate(t,b,b.run())
for v in range(256):
    cpu=CPU(asm,b'',{'c':v},{})
    got,_,_=cpu.run(max_steps=600)
    want=v-32 if 97<=v<=122 else v
    assert (got&255)==want,(v,got,want)
print('PASS 256 unsigned-char cases; exploratory upper_char image contribution',info['instruction_bytes'])
