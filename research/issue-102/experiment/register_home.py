"""Whole-CFG *register-as-the-home* experiment for nonescaped byte locals.

This differs from a cache: the original local's STA never executes.  The
machine register **is** the C value's home across blocks/backedges. Only
select if every load has the register on every predecessor path, all X/Y
original uses remain unmodified, and no call/clobber crosses the live range.
A store becomes TAX/TAY only when NZ(A) is known equal to old NZ (to preserve
6502 branch semantics) and the register is dead at that point.
"""
from pathlib import Path
import re,json,collections
from pycparser import c_parser,c_ast
from machine_locations import instr,graph,split_functions,live_hardware,XDEF,YDEF
HERE=Path(__file__).resolve().parent
NZ_A={'lda','adc','sbc','and','ora','eor','txa','tya','pla'}
NZ_NO={'clc','sec','cld','sed','cli','sei','clv','sta','stx','sty','jmp','nop'}

def nz_matches_A(lines,i):
 # Conservative local proof; never cross an unknown label/control boundary.
 for k in range(i-1,max(-1,i-7),-1):
  line=lines[k]
  if line.endswith(':'):return False
  op,arg=instr(line)
  if op in NZ_A:return True
  if op in NZ_NO:continue
  return False
 return False

def candidate_plan(lines,name,candidate,reg,rt):
 n=len(lines);succ,pred=graph(lines);live=live_hardware(lines,succ,reg,rt)
 # Only ordinary A-source stores and A loads may refer to this local byte.
 ids=[];writes=[]
 for i,l in enumerate(lines):
  op,arg=instr(l)
  if arg==candidate:
   if op=='lda':ids.append(i)
   elif op=='sta':writes.append(i)
   else:return None
 if not ids or not writes:return None
 if not all(not live[i] and nz_matches_A(lines,i) for i in writes):return None
 # Evaluate a *must-resident* machine-register fact on CFG. No speculative
 # use at joins, and reject any load not dominated by a store on all paths.
 inn=[True]*n;out=[True]*n
 for step in range(2*n+10):
  changed=False
  for i,l in enumerate(lines):
   op,arg=instr(l)
   newin=all(out[j] for j in pred[i]) if pred[i] else False
   if op=='sta' and arg==candidate:newout=True
   elif op in (XDEF if reg=='x' else YDEF):newout=False
   else:newout=newin
   if inn[i]!=newin or out[i]!=newout:
    inn[i]=newin;out[i]=newout;changed=True
  if not changed:break
 else:raise RuntimeError('reg-home fixed-point failure')
 if any(not inn[i] for i in ids):return None
 # Cheap safety: an X/Y register is not live at a chosen STA; and no
 # missing source-local load may bypass cached version.
 new=[]
 for i,l in enumerate(lines):
  op,arg=instr(l)
  if op=='sta' and arg==candidate:new.append('    ta'+reg)
  elif op=='lda' and arg==candidate:new.append('    t'+reg+'a')
  else:new.append(l)
 return new,{'candidate':candidate,'reg':reg,'writes':len(writes),'reads':len(ids),'bytes_saved':2*(len(writes)+len(ids))}

def main():
 src=re.sub(r'/\*.*?\*/','',(HERE/'full_corpus/ass.c').read_text(),flags=re.S)
 fns={f.decl.name:f for f in c_parser.CParser().parse(src).ext if isinstance(f,c_ast.FuncDef)}
 # Exclude params: caller ABI writes private formal-parameter homes before
 # entry, so removing that external write would change call semantics.
 char_locals={}
 for name,f in fns.items():
  names=set()
  for d in f.body.block_items or []:
   if isinstance(d,c_ast.Decl) and isinstance(d.type,c_ast.TypeDecl) and d.type.type.names==['char']:
    names.add('__L_'+name+'_'+d.name)
  char_locals[name]=names
 lines=(HERE/'functions.asm').read_text().splitlines();sects=split_functions(lines,set(fns))
 out=[];pos=0;stats=[]
 for name,a,b in sects:
  old=lines[a:b];rt='u8' if fns[name].decl.type.type.type.names==['char'] else 's16'
  best=None
  for candidate in char_locals[name]:
   for reg in ('x','y'):
    proposed=candidate_plan(old,name,candidate,reg,rt)
    if proposed and (best is None or proposed[1]['bytes_saved']>best[1]['bytes_saved']):best=proposed
  out.extend(lines[pos:a]);out.extend(best[0] if best else old);pos=b
  if best:stats.append({'function':name,**best[1]})
 out.extend(lines[pos:]);(HERE/'functions.asm').write_text('\n'.join(out)+'\n')
 (HERE/'register_home_stats.json').write_text(json.dumps(stats,indent=2))
 print('whole-CFG physical register HOMES',len(stats),'savings',sum(x['bytes_saved'] for x in stats),'top',stats[:10])
if __name__=='__main__':main()
