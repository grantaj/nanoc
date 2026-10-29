"""Research-only interprocedural **live-range** ZP register-file allocator.

Scans exact generated machine instructions, recovers private scalar uses and
writes, solves backward CFG liveness and interference (including callee ABI
parameter writes / callee call clobbers), and colours *actual physical byte
homes* into a bounded pool.  Unlike the earlier function-level call-graph
overlay, unrelated locals can share ZP when their lifetimes do not overlap
inside one function or across a function call. No source-function patterns.
This is an attribution prototype, NOT yet ROM-safe zero-page ownership.
"""
from pathlib import Path
from collections import Counter,defaultdict
import json,re,os
from pycparser import c_parser,c_ast
P=Path(__file__).resolve().parent
sym=json.loads((P/'symbols.json').read_text());sizes=json.loads((P/'local_storage.json').read_text())
original=dict(sym)
# local or callee-static parameter aliases only, no globals
nodes=set(sizes)
addr_to_node={original[n]:n for n in nodes}
name_to_node={n:n for n in nodes}
for n,a in original.items():
 if n.startswith('__call_') and a in addr_to_node:name_to_node[n]=addr_to_node[a]
text=(P/'functions.asm').read_text().splitlines()
starts=[(i,m.group(1)) for i,l in enumerate(text) if (m:=re.fullmatch(r'([a-zA-Z][\w]*):',l))]
starts.append((len(text),'__END__'))
functions={f:text[st:ed] for (st,f),(ed,_) in zip(starts,starts[1:])}
USE={'lda','ldx','ldy','cmp','cpx','cpy','adc','sbc','and','ora','eor','bit','inc','dec','asl','lsr','rol','ror'}
WRITE={'sta','stx','sty','inc','dec','asl','lsr','rol','ror'}
BR={'beq','bne','bcc','bcs','bmi','bpl','bvc','bvs'}
parsed={};localrefs=Counter();edges=defaultdict(set);liveness={};interf=defaultdict(set)
for f,lines in functions.items():
 labels={l[:-1]:i for i,l in enumerate(lines) if l.endswith(':')}
 rows=[]
 for i,l in enumerate(lines):
  m=re.match(r'^\s*([a-z]{3})(?:\s+(.*))?$',l)
  op,arg=(m.group(1),(m.group(2) or '').strip()) if m else (None,'')
  # Also handle name+1 aliases as same physical 16-bit variable.
  base=arg.split('+')[0] if arg else ''
  var=name_to_node.get(base)
  u={var} if var and op in USE else set()
  w={var} if var and op in WRITE else set()
  if var:localrefs[var]+=1
  callee=arg if op=='jsr' and arg in functions else None
  if callee:edges[f].add(callee)
  # A function's ABI params are used by its call even when it may not read
  # every one; the caller has already staged the slots at this point.
  if callee:
   ps=sorted((n for n in nodes if n.startswith('__L_'+callee+'_')),key=len)
   # Select only real parameter slots derived from the ABI aliases.
   u.update(name_to_node[k] for k in original if k.startswith('__call_'+callee+'_') and k in name_to_node)
  if op=='rts':successors=[]
  elif op=='jmp':successors=[labels[arg]] if arg in labels else []
  elif op in BR:successors=([labels[arg]] if arg in labels else [])+([i+1] if i+1<len(lines) else [])
  else:successors=[i+1] if i+1<len(lines) else []
  rows.append((op,arg,u,w,successors,callee))
 parsed[f]=rows

# Call-graph reachability + no recursive C function calls.
reach={f:set() for f in functions}
for f in functions:
 todo=list(edges[f])
 while todo:
  g=todo.pop()
  if g in reach[f]:continue
  reach[f].add(g);todo.extend(edges[g])
assert all(f not in reach[f] for f in functions)
for f,rows in parsed.items():
 n=len(rows);livein=[set() for _ in rows];liveout=[set() for _ in rows]
 for _ in range(n*4+4):
  changed=False
  for i in reversed(range(n)):
   op,arg,u,w,successors,callee=rows[i]
   out=set().union(*(livein[j] for j in successors)) if successors else set()
   inn=(out-w)|u
   if inn!=livein[i] or out!=liveout[i]:livein[i]=inn;liveout[i]=out;changed=True
  if not changed:break
 else:raise RuntimeError('no liveness fixed point '+f)
 liveness[f]=(livein,liveout)
 for i,(op,arg,u,w,successors,callee) in enumerate(rows):
  live=livein[i]|liveout[i]|w|u
  for a in live:
   for b in live-{a}:interf[a].add(b);interf[b].add(a)
  # All parent live variables, including staged callee argument slots, must
  # remain disjoint from every possible child static location used by that
  # call chain (our chosen symbolic *static* ABI does not save parent homes).
  if callee:
   descendant={callee}|reach[callee]
   childvars={n for n in nodes if any(n.startswith('__L_'+g+'_') for g in descendant)}
   for a in live:
    for b in childvars-{a}:interf[a].add(b);interf[b].add(a)

# Explicitly coalesce only when liveness says noninterfering; a byte/word home
# is an indivisible interval and must be disjoint from all interfering homes.
BUDGET=int(os.environ.get('ZP_BUDGET','16'))
BASE=int(os.environ.get('ZP_BASE','0x11'),0)
assert 0x11<=BASE and BASE+BUDGET<=0x80, (BASE,BUDGET)
# Use exact linked baseline instruction reference count for value, including
# all call aliases; prefer high access frequency per byte.
order=sorted(nodes,key=lambda n:(localrefs[n]/sizes[n],localrefs[n],n),reverse=True)
assigned={}
for n in order:
 if localrefs[n]==0:continue
 width=sizes[n]
 for off in range(BUDGET-width+1):
  if any(k in interf[n] and off<koff+sizes[k] and koff<off+width for k,koff in assigned.items()):continue
  assigned[n]=off;break
for n,off in assigned.items():
 old=original[n];sym[n]=BASE+off
 for alias in original:
  if alias.startswith('__call_') and original[alias]==old:sym[alias]=BASE+off
for a in assigned:
 for b in interf[a]:
  if b in assigned:
   assert assigned[a]+sizes[a]<=assigned[b] or assigned[b]+sizes[b]<=assigned[a],(a,b)
(P/'symbols.json').write_text(json.dumps(sym,indent=2))
summary={'base':BASE,'budget':BUDGET,'allocated':len(assigned),'references':sum(localrefs[n] for n in assigned),'logical_bytes':sum(sizes[n] for n in assigned),'max_offset':max((v+sizes[k] for k,v in assigned.items()),default=0),'mapping':{n:BASE+i for n,i in assigned.items()}}
(P/'live_home_stats.json').write_text(json.dumps(summary,indent=2))
print({k:v for k,v in summary.items() if k!='mapping'})
