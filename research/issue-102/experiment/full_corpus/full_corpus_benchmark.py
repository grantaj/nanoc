#!/usr/bin/env python3
"""Research-only exact-source whole-function coverage/size probe.
Not an executable C64 program and not a full compiler: no untested function is credited.
"""
from pathlib import Path
from collections import Counter
import re, copy, json, csv, traceback
from pycparser import c_parser, c_ast, c_generator
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend,LocalArgumentBackend
from execute6502 import relax

HERE=Path(__file__).parent
raw=(HERE/'exact_source'/'ass.c').read_text()
src=re.sub(r'/\*.*?\*/','',raw,flags=re.S)
ast=c_parser.CParser().parse(src)
funcs=[node for node in ast.ext if isinstance(node,c_ast.FuncDef)]
globals=[node for node in ast.ext if isinstance(node,c_ast.Decl)]
gen=c_generator.CGenerator()
# Retain global array/pointer/word layouts but not giant static initialisers.
globstubs=[]
for d in globals:
 d=copy.deepcopy(d);d.init=None
 globstubs.append(gen.visit(d)+';')
protos=[gen.visit(f.decl)+';' for f in funcs]
protos+=['int io_open(char *name, int length);','int io_read(int handle);','char io_close(int handle);']
prefix='\n'.join(globstubs+protos)+'\n'
# Array element width is relevant even when the array decays to a pointer.
arrays={}
for d in globals:
 if isinstance(d.type,c_ast.ArrayDecl):
  elem=d.type.type
  while isinstance(elem,c_ast.ArrayDecl):elem=elem.type
  elemtype='u8' if isinstance(elem,c_ast.TypeDecl) and elem.type.names==['char'] else 'u16' if isinstance(elem,c_ast.TypeDecl) and elem.type.names==['unsigned'] else 's16'
  n=int(d.type.dim.value) if isinstance(d.type.dim,c_ast.Constant) else 0
  arrays[d.name]=(elemtype,n)

outdir=HERE/'whole_corpus';outdir.mkdir(exist_ok=True)
(outdir/'arrays.json').write_text(json.dumps(arrays))
results=[]
for i,f in enumerate(funcs):
 name=f.decl.name
 source=prefix+gen.visit(f)+'\n'
 (outdir/(name+'.c')).write_text(source)
 row=dict(name=name,source_lines=gen.visit(f).count('\n')+1,tape_status='untried',ops=0,blocks=0,values=0)
 try:
  t=TapeBuilder(source).build()
  row.update(tape_status='ok',ops=sum(len(b.ops) for b in t.blocks),blocks=len(t.blocks),values=t.nextvalue)
  for label,cls in [('local',LocalArgumentBackend),('cross',ArgumentPlacementBackend)]:
   try:
    b=cls(t,arrays)
    code=b.run();patched,bytecount,repairs=relax(code)
    (outdir/(name+'.'+label+'.asm')).write_text(patched)
    row.update({label+'_status':'ok',label+'_bytes':bytecount,label+'_branches':repairs,label+'_values_materialized':len(set(re.findall(r'__v(\d+)',code)))})
   except Exception as e:
    row[label+'_status']='error';row[label+'_error']=type(e).__name__+': '+str(e)
 except Exception as e:
  row['tape_status']='error';row['tape_error']=type(e).__name__+': '+str(e)
 results.append(row)
 print(f'{i+1:2d}/44 {name:31s} {row["tape_status"]:5s} {row.get("local_bytes","-")!s:>6} {row.get("cross_bytes","-")!s:>6} {row.get("tape_error",row.get("local_error",""))[:75]}',flush=True)
fields=list(dict.fromkeys(k for r in results for k in r))
with open(outdir/'coverage.csv','w',newline='') as file:
 w=csv.DictWriter(file,fieldnames=fields);w.writeheader();w.writerows(results)
(outdir/'coverage.json').write_text(json.dumps(results,indent=2))
print('\\nSUMMARY',Counter(r['tape_status'] for r in results),Counter(r.get('local_status') for r in results),Counter(r.get('cross_status') for r in results))
print('bytes of fully lowered (LOCAL only)',sum(r.get('local_bytes',0) for r in results))
