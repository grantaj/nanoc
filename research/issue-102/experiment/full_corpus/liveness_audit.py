"""CFG dataflow audit (not an allocation implementation): max concurrently
live *materialised* typed-tape value IDs vs unique temporary identifiers.
"""
from pathlib import Path
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend
from execute6502 import relax
from collections import defaultdict
import re

def source_values(o,defs):
    c,a=o.code,o.args
    if c in ('return','branch'):v=a[:1]
    elif c=='call':v=a[1:]
    elif c=='store':v=a[1:]
    elif c in ('read','+','-','*','<<','>>','&','|','^','==','!=','<','<=','>','>=','neg','not'):v=a
    else:v=()
    return set(x for x in v if isinstance(x,int) and x in defs)

def audit(fn,arr):
 t=TapeBuilder(Path(fn+'.c').read_text()).build();b=ArgumentPlacementBackend(t,arr)
 asm,sz,_=relax(b.run());slots=set(int(x) for x in re.findall(r'__v(\d+)',asm))
 blocks={q.name:q for q in t.blocks if q.name in b.reach}
 succ={q.name:[x for x in b.succ(q) if x in blocks] for q in blocks.values()}
 uses={};defs={};all_defs=b.defs
 for q in blocks.values():
  used=set();defined=set()
  for o in q.ops:
   used|=(source_values(o,all_defs)-defined)
   if o.result>=0:defined.add(o.result)
  uses[q.name]=used;defs[q.name]=defined
 ins={q:set() for q in blocks};outs={q:set() for q in blocks}
 for _ in range(1000):
  updated=False
  for q in reversed(t.blocks):
   if q.name not in blocks:continue
   out=set.union(*(ins[x] for x in succ[q.name])) if succ[q.name] else set()
   inn=uses[q.name] | (out-defs[q.name])
   if inn!=ins[q.name] or out!=outs[q.name]:updated=True
   ins[q.name]=inn;outs[q.name]=out
  if not updated:break
 else:raise AssertionError('failed liveness convergence')
 peak=0;peak_bytes=0;cross=set()
 for q in blocks.values():
  live=set(outs[q.name]);cross|=(set(ins[q.name])|set(outs[q.name])) & slots
  for o in reversed(q.ops):
   if o.result>=0:live.discard(o.result)
   live|=source_values(o,all_defs)
   alloc=live&slots
   peak=max(peak,len(alloc))
   peak_bytes=max(peak_bytes,sum(1 if t.values[v] in ('u8','bool') else 2 for v in alloc))
 capacity=sum(1 if t.values[v] in ('u8','bool') else 2 for v in slots)
 return dict(function=fn,bytes=sz,temporary_ids=len(slots),static_bytes_without_reuse=capacity,maximum_live_ids=peak,maximum_live_bytes=peak_bytes,cross_block_ids=len(cross))
for fn in ('assemble_instruction','parse_value','process_source_line','parse_atom'):
 ar={'source_line':('u8',256)} if fn=='process_source_line' else {'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if fn=='parse_atom' else {}
 print(audit(fn,ar))
