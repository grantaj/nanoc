"""Independent proof checker for experimental C64 machine-value homes.

Uses the generated instruction CFG and original C parameter types, rather than
importing the allocator or trusting its interference graph. Verifies simultaneous
live locations, call-chain overlap, and parameter-slot aliases. Also injects an
intentional bad overlap and demands that the checker reject it.

This checks a conservative NON-ESCAPING static-local model, not KERNAL's use of
zero page, IRQ behavior, or native C64 execution.
"""
from pathlib import Path
from collections import defaultdict
import json, re
from pycparser import c_parser,c_ast

ROOT=Path(__file__).resolve().parent
symbols=json.loads((ROOT/'symbols.json').read_text())
sizes=json.loads((ROOT/'local_storage.json').read_text())
source=re.sub(r'/\*.*?\*/','',(ROOT/'full_corpus/ass.c').read_text(),flags=re.S)
asts=c_parser.CParser().parse(source)
functions={f.decl.name:f for f in asts.ext if isinstance(f,c_ast.FuncDef)}
for n in c_ast.NodeVisitor.__mro__: pass
class Escape(c_ast.NodeVisitor):
 def visit_UnaryOp(self,node):
  assert node.op!='&','local address escape requires a different allocation proof'
  self.generic_visit(node)
Escape().visit(asts)

# Recover ABI parameter identity semantically, not from the resulting coalesced
# physical address (which could make two different variables have the same addr).
node_for={name:name for name in sizes}
param_edges={}
for f,definition in functions.items():
 ft=definition.decl.type
 if not ft.args: continue
 for i,arg in enumerate(ft.args.params):
  if isinstance(arg,c_ast.EllipsisParam):continue
  alias=f'__call_{f}_{i}'
  node=f'__L_{f}_{arg.name}'
  if alias in symbols and node in sizes:
   node_for[alias]=node
   param_edges[alias]=node

BR={'bcc','bcs','beq','bne','bmi','bpl','bvc','bvs'}
USE={'lda','ldx','ldy','cmp','cpx','cpy','adc','sbc','and','ora','eor','bit','inc','dec','asl','lsr','rol','ror'}
WRITE={'sta','stx','sty','inc','dec','asl','lsr','rol','ror'}
lines=(ROOT/'functions.asm').read_text().splitlines()
marks=[(i,l[:-1]) for i,l in enumerate(lines) if l.endswith(':') and l[:-1] in functions]
marks.append((len(lines),'END'))
assert len(marks)-1==44
calls=defaultdict(set)
segments={}
for (i,f),(j,_) in zip(marks,marks[1:]):
 seg=lines[i:j]; lbl={s[:-1]:k for k,s in enumerate(seg) if s.endswith(':')}
 rows=[]
 for k,line in enumerate(seg):
  m=re.match(r'^\s*([a-z]{3})(?:\s+(.*))?$',line)
  op,arg=(m.group(1),(m.group(2) or '').strip()) if m else ('','')
  key=arg.split('+')[0]
  var=node_for.get(key)
  read={var} if var and op in USE else set()
  write={var} if var and op in WRITE else set()
  callee=arg if op=='jsr' and arg in functions else None
  if callee:
   calls[f].add(callee)
   read.update(param_edges[name] for name in param_edges if name.startswith(f'__call_{callee}_'))
  if op=='rts':suc=[]
  elif op=='jmp':suc=[lbl[arg]] if arg in lbl else []
  elif op in BR:suc=([lbl[arg]] if arg in lbl else [])+([k+1] if k+1<len(seg) else [])
  else:suc=[k+1] if k+1<len(seg) else []
  rows.append((read,write,suc,callee))
 segments[f]=rows

reachable={f:set() for f in functions}
for f in functions:
 stack=list(calls[f]);seen=set()
 while stack:
  g=stack.pop()
  if g in seen:continue
  seen.add(g);stack.extend(calls[g])
 assert f not in seen,'recursive calls invalidate overlay argument'
 reachable[f]=seen

# Independently derive the full machine-liveness relation.
live={}; conflicts=set(); checked=0
for f,rows in segments.items():
 inside=[set() for _ in rows]; outside=[set() for _ in rows]
 for _ in range(len(rows)*4+4):
  changed=False
  for k in range(len(rows)-1,-1,-1):
   read,write,suc,_=rows[k]
   outgoing=set().union(*(inside[j] for j in suc)) if suc else set()
   incoming=read | (outgoing-write)
   if incoming!=inside[k] or outgoing!=outside[k]:
    changed=True;inside[k]=incoming;outside[k]=outgoing
  if not changed:break
 else:raise AssertionError('liveness did not converge')
 for k,(r,w,s,callee) in enumerate(rows):
  here=inside[k]|outside[k]|r|w
  for n in here:
   for m in here-{n}:
    conflicts.add(tuple(sorted((n,m))))
  if callee:
   scope={callee}|reachable[callee]
   descendants={n for n in sizes if any(n.startswith('__L_'+x+'_') for x in scope)}
   for n in here:
    for m in descendants-{n}:conflicts.add(tuple(sorted((n,m))))
  checked+=1

# Check allocated physical intervals at every proven interference edge.
def collision(a,b,physical):
 a0=physical[a]; b0=physical[b]
 return a0<b0+sizes[b] and b0<a0+sizes[a]

def validate(physical):
 return [(a,b) for a,b in conflicts if a in physical and b in physical and collision(a,b,physical)]

assigned={n:symbols[n] for n in sizes if 0x11 <= symbols[n] < 0x80}
# This filter deliberately includes only promoted homes; normal statics live
# at $4xxx and above. Explicitly bound them to a 16-byte window via env/report.
meta=json.loads((ROOT/'live_home_stats.json').read_text())
base=meta['base'];budget=meta['budget']
assigned={n:int(addr) for n,addr in meta['mapping'].items()}
assert len(assigned)==meta['allocated']
assert all(base <= a and a+sizes[n] <= base+budget for n,a in assigned.items())
assert not validate(assigned),'overlapping live homes'
for alias,node in param_edges.items():
 if node in assigned and alias in symbols:assert symbols[alias]==assigned[node],(alias,node)

# Deliberately corrupt one proven conflict and verify the checker would fail.
adversarial=next(((a,b) for a,b in conflicts if a in assigned and b in assigned and sizes[a]==sizes[b] and assigned[a]!=assigned[b]),None)
assert adversarial,'missing independently detectable negative case'
bad=dict(assigned);a,b=adversarial;bad[a]=bad[b]
assert validate(bad),('deliberate aliasing error went undetected',a,b)
result={'byte_budget':budget,'base':base,'allocated_values':len(assigned),'verified_machine_nodes':checked,'interference_edges':len(conflicts),'call_edges':sum(map(len,calls.values())),'bad_overlap_detected':list(adversarial),'param_aliases_checked':sum(n in assigned for n in param_edges.values())}
(ROOT/'independent_location_check.json').write_text(json.dumps(result,indent=2))
print('PASS:',result)
