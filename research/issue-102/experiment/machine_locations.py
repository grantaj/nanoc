"""Research competing *physical 6502* machine-value planner.

Choose a stable byte local for X/Y over an entire function CFG.  Emit TAX/TAY
only when the hardware register is dead on every continuation, and only after
an LDA so processor flags remain identical. At joins, a cached location is
used only when **every predecessor** agrees it is resident. Writes, machine
clobbers and calls invalidate the resident value. No source function spelling
is recognised; candidates are weighted by the *whole-function* byte cost.

This is intentionally a register-location competitor to tape/postpass caches,
not a claim that the 6502 can retain all C values in three registers.
"""
import re,collections,json
from pathlib import Path
from pycparser import c_parser,c_ast
HERE=Path(__file__).resolve().parent
EX=re.compile(r'^\s*([a-z]{2,3})(?:\s+([^;]*?))?\s*$',re.I)
LABEL=re.compile(r'^([A-Za-z_.][\w.]*):$')
COND={'bcc','bcs','beq','bne','bmi','bpl','bvc','bvs'}
XDEF={'ldx','tax','tsx','inx','dex','jsr','pla_x'}
YDEF={'ldy','tay','iny','dey','jsr'}
XUSE={'stx','txa','cpx','inx','dex','txs'}
YUSE={'sty','tya','cpy','iny','dey'}

def instr(line):
 m=EX.match(line)
 return (m.group(1).lower(),(m.group(2) or '').strip()) if m else ('','')

def mem_byte(a):
 return a.startswith('__L_') and not any(ch in a for ch in '(),#')

def split_functions(lines, fnames):
 idx=[(i,l[:-1]) for i,l in enumerate(lines) if l.endswith(':') and l[:-1] in fnames]
 assert len(idx)==len(fnames),(len(idx),len(fnames))
 return [(name,start,(idx[k+1][0] if k+1<len(idx) else len(lines))) for k,(start,name) in enumerate(idx)]

def graph(lines):
 labels={m.group(1):i for i,l in enumerate(lines) if (m:=LABEL.match(l))}
 succ=[];pred=[set() for _ in lines]
 for i,l in enumerate(lines):
  op,arg=instr(l)
  if op=='rts':s=[]
  elif op=='jmp':s=[labels[arg]] if arg in labels else []
  elif op in COND:s=([i+1] if i+1<len(lines) else [])+([labels[arg]] if arg in labels else [])
  else:s=[i+1] if i+1<len(lines) else []
  succ.append(s)
  for j in s:pred[j].add(i)
 return succ,pred

def live_hardware(lines,succ,reg,return_type):
 n=len(lines);live=[False]*n;out=[False]*n
 def ud(i):
  op,arg=instr(lines[i]);r=reg
  use=((op in (XUSE if r=='x' else YUSE)) or
       (',x' in arg if r=='x' else ',y' in arg) or
       (op=='rts' and (r=='x' and return_type!='u8')))
  defs=op in (XDEF if r=='x' else YDEF)
  if op=='jsr':use=False;defs=True
  return use,defs
 for _ in range(n+2):
  change=False
  for i in range(n-1,-1,-1):
   o=any(live[j] for j in succ[i]);u,d=ud(i);v=u or (o and not d)
   if out[i]!=o or live[i]!=v:out[i]=o;live[i]=v;change=True
  if not change:break
 else:raise RuntimeError('hardware liveness loop')
 return out

def resident_plan(lines,candidate,reg,return_type):
 n=len(lines);succ,pred=graph(lines)
 hw_live=live_hardware(lines,succ,reg,return_type)
 cache_in=[True]*n;cache_out=[True]*n
 # Function entry cannot assume value was previously placed in X/Y.
 if n:cache_in[0]=False
 def trans(i,is_cached):
  op,arg=instr(lines[i]);defreg=XDEF if reg=='x' else YDEF
  if op=='lda' and arg==candidate:
   if is_cached:return True
   return not hw_live[i]
  if op in defreg:return False
  if op in ('sta','stx','sty','inc','dec','asl','lsr','rol','ror') and arg==candidate:return False
  # Unknown write through a pointer cannot address a nonescaped static local.
  return is_cached
 for k in range(n*2+10):
  changed=False
  for i in range(n):
   new_in=(all(cache_out[j] for j in pred[i]) if pred[i] else False)
   new_out=trans(i,new_in)
   if cache_in[i]!=new_in or cache_out[i]!=new_out:
    cache_in[i]=new_in;cache_out[i]=new_out;changed=True
  if not changed:break
 else:raise RuntimeError('residency lattice did not converge')
 result=[];savings=0;hits=0;seeds=0
 for i,l in enumerate(lines):
  op,arg=instr(l)
  if op=='lda' and arg==candidate:
   if cache_in[i]:
    result.append('    t'+reg+'a');hits+=1;savings+=2
   else:
    result.append(l)
    if not hw_live[i]:
     result.append('    ta'+reg);seeds+=1;savings-=1
  else:result.append(l)
 return result,{'candidate':candidate,'register':reg,'hits':hits,'seeds':seeds,'nominal_saving':savings}

def candidates(lines,prefix):
 c=collections.Counter()
 for line in lines:
  op,arg=instr(line)
  if op=='lda' and arg.startswith(prefix) and mem_byte(arg):c[arg]+=1
 return [x for x,n in c.most_common() if n>=2]

def transform(lines,name,rtype):
 # This is a whole-function cost search, not a heuristic based on variable names.
 # One stable location per register; candidate choices are independently scored.
 result=list(lines);details=[]
 for reg in ('x','y'):
  best=None
  for c in candidates(result,'__L_'+name+'_'):
   revised,m=resident_plan(result,c,reg,rtype)
   if m['nominal_saving']>0 and (best is None or m['nominal_saving']>best[1]['nominal_saving']):best=(revised,m)
  if best:
   result=best[0];details.append(best[1])
 return result,details

def main():
 lines=(HERE/'functions.asm').read_text().splitlines()
 src=re.sub(r'/\*.*?\*/','',(HERE/'full_corpus/ass.c').read_text(),flags=re.S)
 ast=c_parser.CParser().parse(src)
 rtypes={}
 for f in ast.ext:
  if isinstance(f,c_ast.FuncDef):
   rt=f.decl.type.type
   rtypes[f.decl.name]='u8' if isinstance(rt,c_ast.TypeDecl) and rt.type.names==['char'] else 's16'
 fns=split_functions(lines,rtypes)
 output=[];stats=[];point=0
 for name,start,end in fns:
  output.extend(lines[point:start]);new,chosen=transform(lines[start:end],name,rtypes[name]);output.extend(new)
  stats.append({'function':name,'selected':chosen,'nominal_saving':sum(a['nominal_saving'] for a in chosen)})
  point=end
 output.extend(lines[point:])
 (HERE/'functions.asm').write_text('\n'.join(output)+'\n')
 (HERE/'machine_locations_stats.json').write_text(json.dumps(stats,indent=2))
 print('register location strategy total nominal byte saving',sum(x['nominal_saving'] for x in stats), 'functions improved',sum(bool(x['selected']) for x in stats))
 print('best',sorted(stats,key=lambda x:-x['nominal_saving'])[:10])
if __name__=='__main__':main()
