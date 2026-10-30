"""Research-only exact-value live-range graph colouring across tape CFG.
Allocation uses low-byte/high-byte slots and keeps storage disjoint for any
values simultaneously live during a semantic operation. It is not yet
mapped to a proven free C64 zero-page physical address region.
"""
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend
from collections import defaultdict
from execute6502 import relax
import execute6502
from pathlib import Path
import re,csv

def sources(o,defs):
 c,a=o.code,o.args
 if c in ('return','branch'):v=a[:1]
 elif c=='call':v=a[1:]
 elif c=='store_index':v=a
 elif c=='store':v=a[1:]
 elif c in ('read','+','-','*','<<','>>','|','&','^','==','!=','<','<=','>','>=','neg','not','identity','low8','high8'):v=a
 else:v=()
 return set(x for x in v if isinstance(x,int) and x in defs)

def allocate(t,backend,raw):
 slots=set(int(x) for x in re.findall(r'__v(\d+)',raw))
 blocks={b.name:b for b in t.blocks if b.name in backend.reach}
 def successors(b):
  if hasattr(backend,'succ'):return backend.succ(b)
  term=b.ops[-1]
  if term.code=='jump':return [term.args[0]]
  if term.code=='branch':return list(term.args[1:])
  return []
 successor={b.name:[x for x in successors(b) if x in blocks] for b in blocks.values()}
 used,defined={},{}
 for b in blocks.values():
  u=set();d=set()
  for op in b.ops:
   u |= sources(op,backend.defs)-d
   if op.result>=0:d.add(op.result)
  used[b.name],defined[b.name]=u,d
 live_in={n:set() for n in blocks};live_out={n:set() for n in blocks}
 for _ in range(10000):
  changed=False
  for b in reversed(t.blocks):
   if b.name not in blocks:continue
   successors=successor[b.name];out=set().union(*(live_in[n] for n in successors)) if successors else set()
   inn=used[b.name] | (out-defined[b.name])
   if inn!=live_in[b.name] or out!=live_out[b.name]:changed=True
   live_in[b.name],live_out[b.name]=inn,out
  if not changed:break
 else:raise RuntimeError('liveness did not reach fixed point')
 conflicts={v:set() for v in slots};peak=0;peak_bytes=0
 widths={v:1 if t.values[v] in ('u8','bool') else 2 for v in slots}
 for b in blocks.values():
  active=set(live_out[b.name]);
  for op in reversed(b.ops):
   after=active.copy()
   if op.result>=0:active.discard(op.result)
   # A shared caller-scratch zero-page temporary is only legal if no value
   # is live THROUGH a call. Reject this physical-location plan otherwise.
   # The IR representation itself does not have this restriction.
   if op.code=='call' and (active & slots):
    raise ValueError('caller-scratch ABI violation: values live through call '+str(sorted(active & slots)))
   active|=sources(op,backend.defs)
   # Treat sources and destinations as interfering during the entire
   # instruction sequence implementing this semantic op.
   simultaneous=(active|after)&slots
   peak=max(peak,len(simultaneous));peak_bytes=max(peak_bytes,sum(widths[v] for v in simultaneous))
   for v in simultaneous:conflicts[v] |= simultaneous-{v}
 assigned={}
 for v in sorted(slots,key=lambda x:(-len(conflicts[x]),-widths[x],x)):
  off=0
  while any((off < assigned[u]+widths[u] and assigned[u] < off+widths[v]) for u in conflicts[v] if u in assigned):
   off+=1
  assigned[v]=off
 # Check all graph edges and allocated byte ranges don't overlap.
 for v in slots:
  for u in conflicts[v]:
   assert assigned[v]+widths[v]<=assigned[u] or assigned[u]+widths[u]<=assigned[v]
 nbytes=max((assigned[v]+widths[v] for v in slots),default=0)
 # Every symbolic __tmpK refers to zero-page for experiment. The research
 # interpreter models them as distinct bytes; a real C64 mapping is TBD.
 for off in range(nbytes):execute6502.ZP.add('__tmp'+str(off))
 def subst(m):
  v=int(m.group(1));h=1 if m.group(2) else 0
  return '__tmp'+str(assigned[v]+h)
 revised=re.sub(r'__v(\d+)(\+1)?',subst,raw)
 revised,ncode,repairs=relax(revised)
 return revised,dict(temporary_values=len(slots),unpacked_bytes=sum(widths.values()),packed_bytes=nbytes,maximum_simultaneous_values=peak,maximum_simultaneous_bytes=peak_bytes,instruction_bytes=ncode,long_branch_repairs=repairs,shared_locations=nbytes<len(slots))

if __name__=='__main__':
 rows=[]
 for fn in ('assemble_instruction','parse_value','process_source_line','parse_atom'):
  arr={'source_line':('u8',256)} if fn=='process_source_line' else {'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if fn=='parse_atom' else {}
  t=TapeBuilder(Path(fn+'.c').read_text()).build();b=ArgumentPlacementBackend(t,arr)
  code=b.run();out,info=allocate(t,b,code)
  Path(fn+'.packed.asm').write_text(out)
  Path(fn+'.asm').write_text(out)
  rows.append({'function':fn,**info})
  print(fn,info,flush=True)
 with open('packed_metrics.csv','w',newline='') as f:
  w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
