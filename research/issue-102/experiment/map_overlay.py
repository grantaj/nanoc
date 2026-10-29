"""Conservative nonrecursive call-graph overlay of static C locals into a
HYPOTHETICAL zero-page window. ROM/KERNAL safety is NOT established.
All globals interfere with everybody. Same/ancestor-descendant functions
interfere with each other. Sibling functions may overlay, safely for static calls.
"""
from pathlib import Path
from collections import Counter,defaultdict
import json,re,os
from pycparser import c_parser,c_ast
R=Path(__file__).parent
sym=json.loads((R/'symbols.json').read_text());loc=json.loads((R/'local_storage.json').read_text())
s=re.sub(r'/\*.*?\*/','',(R/'full_corpus'/'ass.c').read_text(),flags=re.S)
unit=c_parser.CParser().parse(s)
funcs={f.decl.name:f for f in unit.ext if isinstance(f,c_ast.FuncDef)}
class CallVisitor(c_ast.NodeVisitor):
 def __init__(self):self.targets=set()
 def visit_FuncCall(self,node):
  if isinstance(node.name,c_ast.ID) and node.name.name in funcs:self.targets.add(node.name.name)
  self.generic_visit(node)
edges={}
for n,f in funcs.items():
 v=CallVisitor();v.visit(f.body);edges[n]=v.targets
reach={n:set() for n in funcs}
for n in funcs:
 todo=list(edges[n])
 while todo:
  k=todo.pop()
  if k in reach[n]:continue
  reach[n].add(k);todo.extend(edges[k])
assert all(n not in reach[n] for n in funcs),'recursive calls not safe with this overlay'
for d in unit.ext:
 if not isinstance(d,c_ast.Decl) or d.init is not None:continue
 if isinstance(d.type,c_ast.PtrDecl):loc[d.name]=2
 elif isinstance(d.type,c_ast.TypeDecl):loc[d.name]=1 if d.type.type.names==['char'] else 2

asm=(R/'functions.asm').read_text()
counts=Counter(re.findall(r'(?<![a-zA-Z_0-9])(__L_[a-zA-Z_0-9]+|__call_[a-zA-Z_0-9]+)(?![a-zA-Z_0-9])',asm))
usage={k:0 for k in loc if k in sym}
byaddr=defaultdict(list)
for k in usage:byaddr[sym[k]].append(k)
for n,c in counts.items():
 if n in usage:usage[n]+=c
 elif n in sym and n.startswith('__call_'):
  for k in byaddr.get(sym[n],[]):usage[k]+=c
for n in usage:
 if not n.startswith('__L_'):usage[n]+=len(re.findall(r'(?<![a-zA-Z_0-9])'+re.escape(n)+r'(?![a-zA-Z_0-9])',asm))
fun_names=sorted(funcs,key=len,reverse=True)
def owner(n):
 for f in fun_names:
  if n.startswith('__L_'+f+'_'):return f
 return None

# Variables in parent/callee lifetimes may coexist; siblings may share storage.
def conflicts(a,b):
 x,y=owner(a),owner(b)
 return x is None or y is None or x==y or y in reach[x] or x in reach[y]

BUDGET=int(os.environ.get('ZP_BUDGET','16'))
# Entries use allocation offsets from $11; $02-$10 remain reserved for existing scratch.
alloc={};saved_origin=dict(sym);rows=[]
for n in sorted(usage,key=lambda k:(usage[k]/loc[k],usage[k],k),reverse=True):
 if not usage[n]:continue
 width=loc[n];found=None
 for i in range(BUDGET-width+1):
  if any(conflicts(n,other) and not (i+width<=other_offset or other_offset+loc[other]<=i)
        for other,other_offset in alloc.items()):continue
  found=i;break
 if found is None:continue
 alloc[n]=found
 old=saved_origin[n];sym[n]=0x11+found
 for alias in saved_origin:
  if alias.startswith('__call_') and saved_origin[alias]==old:sym[alias]=0x11+found
 rows.append({'name':n,'function':owner(n),'old':old,'zp':0x11+found,'size':width,'refs':usage[n]})
assert all(not(conflicts(a,b) and not (i+loc[a]<=j or j+loc[b]<=i)) for a,i in alloc.items() for b,j in alloc.items() if a!=b)
(R/'symbols.json').write_text(json.dumps(sym,indent=2))
(R/'zp_overlay.json').write_text(json.dumps(rows,indent=2))
print('budget',BUDGET,'allocated variables',len(rows),'logical bytes',sum(x['size'] for x in rows),
      'refs',sum(x['refs'] for x in rows),'functions',len({x['function'] for x in rows if x['function']}))
print('top 10',[(x['name'],x['zp']) for x in rows[:10]])
