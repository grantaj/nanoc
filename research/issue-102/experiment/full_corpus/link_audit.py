"""Turn per-function research assembly into one collision-free symbolic listing.
Does not allocate a C64 memory map: this is a relocation/ABI *audit*, not a link.
"""
from pathlib import Path
import csv,re,copy,json
from pycparser import c_parser,c_ast
from tape_frontend import TapeBuilder
ROOT=Path(__file__).parent
src=re.sub(r'/\*.*?\*/','',(ROOT/'ass.c').read_text(),flags=re.S)
unit=c_parser.CParser().parse(src)
funcs=[node for node in unit.ext if isinstance(node,c_ast.FuncDef)]
globalnames={x.name for x in unit.ext if isinstance(x,c_ast.Decl)}
asmout=[];renames={};params={};lines_by_fn={}
class Decls(c_ast.NodeVisitor):
 def __init__(self):self.locals=set()
 def visit_Decl(self,node):
  if isinstance(node.type,c_ast.FuncDecl):return
  self.locals.add(node.name)

def replace_tokens(s,m):
 return re.sub(r'(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z_0-9]*)(?![A-Za-z0-9_])',lambda match:m.get(match.group(1),match.group(1)),s)

for f in funcs:
 name=f.decl.name
 lines=(ROOT/'whole_corpus'/(name+'.cross.asm')).read_text().splitlines()
 entries={x.strip()[:-1] for x in lines if x.strip().endswith(':')}
 visitor=Decls();visitor.visit(f.body)
 locals_=visitor.locals
 ps=[]
 if f.decl.type.args:
  ps=[p.name for p in f.decl.type.args.params]
 locals_.update(ps)
 params[name]=ps
 mapping={x:'__F_'+name+'_'+x for x in entries}
 mapping.update({x:'__L_'+name+'_'+x for x in locals_})
 t=TapeBuilder((ROOT/'whole_corpus'/(name+'.c')).read_text()).build()
 mapping.update({x:'__S_'+name+'_'+x for x in t.strings})
 temps=set(re.findall(r'__v\d+', '\n'.join(lines)))
 mapping.update({x:'__T_'+name+'_'+x for x in temps})
 out=[name+':']
 for line in lines:
  s=line.strip()
  if s.endswith(':'):out.append(mapping.get(s[:-1],s[:-1])+':')
  elif s:
   op,sp,arg=s.partition(' ')
   out.append('    '+op+(sp+replace_tokens(arg,mapping) if sp else ''))
 lines_by_fn[name]=out
 renames[name]=mapping
 asmout.extend(out)
 # String bytes aren't included in previous instruction-only cost.
 for lit,data in t.strings.items():
  dest=mapping[lit]
  asmout.append(dest+':')
  asmout.append('    byte '+','.join(str(x) for x in data))

# Every compiler ABI argument slot should alias the callee's static parameter.
for name,ps in params.items():
 for j,p in enumerate(ps):
  asmout.insert(0,f'__call_{name}_{j} = __L_{name}_{p}')
# External IO glue is the only knowingly missing runtime component.
assembly='\n'.join(asmout)+'\n'
(ROOT/'whole_corpus'/'whole_ass_symbolic.asm').write_text(assembly)
from collections import Counter
labels=re.findall(r'^([A-Za-z_][A-Za-z_0-9]*):',assembly,re.M)
duplicates=[(n,c) for n,c in Counter(labels).items() if c>1]
seen=set(labels)|globalnames|set(x for m in renames.values() for x in m.values())
for name,ps in params.items():
 seen.update('__call_'+name+'_'+str(j) for j in range(len(ps)))
seen.update(['__ap','__ix','__rh','__mw'])
needed=set();needslist=[]
for fname,lines in lines_by_fn.items():
 for line in lines:
  s=line.strip()
  if not s or s.endswith(':'):continue
  opcode,_,arg=s.partition(' ')
  # Indexed operands, immediate lo/hi syntax, internal label targets.
  arg=arg.strip().replace(',y','').replace(',x','').replace('(','').replace(')','')
  if not arg:continue
  if arg.startswith('#'):arg=arg[1:]
  if arg.startswith(('<','>')):arg=arg[1:]
  if arg.startswith('$') or re.fullmatch(r'\d+',arg):continue
  m=re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)(?:\+\d+)?',arg)
  if not m:raise ValueError((fname,line))
  sym=m.group(1)
  needed.add(sym)
  if sym not in seen:needslist.append((fname,sym))
print('functions',len(funcs),'labels',len(labels),'duplicate definitions',duplicates,'unresolved refs',sorted(set(needslist))[:25])
print('external refs',sorted(set(sym for _,sym in needslist)))
print('symbolic listing lines',len(asmout),'characters',len(assembly))
(ROOT/'whole_corpus'/'link_audit.json').write_text(json.dumps(dict(functions=len(funcs),labels=len(labels),duplicates=duplicates,unresolved=sorted(set(needslist)),external_refs=sorted(set(sym for _,sym in needslist))),indent=2))
