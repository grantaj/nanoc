"""Research-only *whole-function* physical machine-value flow, not source peepholes.

Analyze the assembled CFG, accounting for real 6502 accumulator contents and
NZ flags. Independently compute backwards *memory-byte liveness* for private
locals and compiler scratch across every successor.  Remove dead materializations
and provably redundant accumulator reloads.  Keep calls/effects as hard clobber
barriers.  The rewriting spans branches and joins and uses the whole function,
not function names or positional templates.
"""
from pathlib import Path
import re,json,collections
P=Path(__file__).resolve().parent
lines=(P/'functions.asm').read_text().splitlines()
fnstarts=[(i,m[1]) for i,s in enumerate(lines) if (m:=re.fullmatch(r'([A-Za-z][\w]*):',s))]
fnstarts.append((len(lines),'__END__'))
BR={'bcc','bcs','beq','bne','bmi','bpl','bvc','bvs'}
STM={'sta','stx','sty'}
READMEM={'lda','ldx','ldy','cmp','cpx','cpy','adc','sbc','and','ora','eor','bit','inc','dec','asl','lsr','rol','ror'}
WRITE={'sta','stx','sty','inc','dec','asl','lsr','rol','ror'}
ASETS={'lda','adc','sbc','and','ora','eor','pla','txa','tya'}
ZN_A={'lda','adc','sbc','and','ora','eor','pla','txa','tya','asl','lsr','rol','ror'}
ZN_NOT_A={'ldx','ldy','tax','tay','inx','iny','dex','dey','cmp','cpx','cpy','bit','inc','dec'}
PRESERVE={'clc','sec','cld','sei','cli','jmp','rts','sta','stx','sty','pha','nop','php','plp'}
local_sizes=json.loads((P/'local_storage.json').read_text())
ops_count=collections.Counter();res={};output=[]

def operand_info(s,fn):
 m=re.match(r'^(__L_'+re.escape(fn)+r'_\w+|__tmp\d+)(\+1)?$',s)
 if m:return m[1]+(m[2] or '')
 return None

def effect(op,arg,fn):
 # All names are direct memory addresses, not indirect addressing.
 v=operand_info(arg,fn)
 use={v} if v is not None and op in READMEM else set()
 write={v} if v is not None and op in WRITE else set()
 return use,write

def cfg(asm):
 label={};ins=[]
 for i,s in enumerate(asm):
  if s.strip().endswith(':'):label[s.strip()[:-1]]=i
 for i,s in enumerate(asm):
  m=re.match(r'^\s*([a-z]{3})(?:\s+(.*))?$',s)
  if m:ins.append((m[1],(m[2] or '').strip()))
  else:ins.append((None,None))
 succ={}
 for i,(op,arg) in enumerate(ins):
  if op=='rts':nxt=[]
  elif op=='jmp':nxt=[label[arg]] if arg in label else []
  elif op in BR:nxt=([label[arg]] if arg in label else [])+([i+1] if i+1<len(ins) else [])
  else:nxt=[i+1] if i+1<len(ins) else []
  succ[i]=nxt
 return ins,succ

def liveness(asm,fn):
 ins,succ=cfg(asm)
 live=[set() for x in asm];liveout=[set() for x in asm]
 for _ in range(len(asm)*2):
  anychange=False
  for i in reversed(range(len(asm))):
   op,arg=ins[i];u,w=effect(op,arg,fn) if op else (set(),set())
   out=set().union(*(live[j] for j in succ[i])) if succ[i] else set()
   ll=(out-w)|u
   if ll!=live[i] or out!=liveout[i]:live[i]=ll;liveout[i]=out;anychange=True
  if not anychange:break
 else:raise RuntimeError('machine byte liveness diverged')
 return ins,succ,live,liveout

# State = (A's known memory homes frozenset, NZ matches A boolean). Each
# predecessor must agree on a location. Optional NZ flag is an AND at joins.
# Transfer with a *real* write removes invalidated locations; an indirect
# store / unknown call discards every identity.
def transfer(op,arg,h,nz,fn):
 h=set(h)
 if op=='lda':
  # only stable direct memory locations are trusted as A homes
  h={arg} if re.fullmatch(r'[\w]+(?:\+1)?',arg) and not arg.startswith('#') else set()
  nz=True
 elif op in ('sta',):
  if re.fullmatch(r'[\w]+(?:\+1)?',arg) and not arg.startswith('#'):h.add(arg)
  else:h.clear()
 elif op in ('stx','sty','inc','dec','asl','lsr','rol','ror') and arg:
  h.discard(arg)
  if op not in ('stx','sty'):nz=False
 elif op in ZN_A:
  h.clear();nz=True
 elif op in ZN_NOT_A:
  nz=False
 elif op in ('jsr','plp'):
  h.clear();nz=False
 elif op in PRESERVE or op in BR:
  pass
 elif op is None:
  pass
 else:
  h.clear();nz=False
 return frozenset(h),nz

def a_must(asm,fn):
 ins,succ=cfg(asm)
 pred={i:set() for i in range(len(asm))}
 for i,nxt in succ.items():
  for j in nxt:pred[j].add(i)
 out=[(frozenset(),False) for _ in asm];enter=[(frozenset(),False) for _ in asm]
 for _ in range(len(asm)*3):
  changed=False
  for i,(op,arg) in enumerate(ins):
   if i==0 or not pred[i]:val=(frozenset(),False)
   else:
    ps=[out[j] for j in pred[i]]
    hh=set(ps[0][0]);zz=ps[0][1]
    for h,n in ps[1:]:hh.intersection_update(h);zz=zz and n
    val=frozenset(hh),zz
   val2=transfer(op,arg,*val,fn)
   if enter[i]!=val or out[i]!=val2:
    enter[i]=val;out[i]=val2;changed=True
  if not changed:break
 else:raise RuntimeError('machine A must analysis diverged')
 return ins,enter

for (st,fn),(ed,_) in zip(fnstarts,fnstarts[1:]):
 asm=lines[st:ed]
 # Repeated fixed-point deletion of stores exposes more liveness opportunities.
 for _ in range(6):
  ins,succ,live,liveout=liveness(asm,fn)
  deletes=set()
  for i,(op,arg) in enumerate(ins):
   if op not in STM:continue
   loc=operand_info(arg,fn)
   if loc and loc not in liveout[i]:deletes.add(i)
  if not deletes:break
  asm=[x for i,x in enumerate(asm) if i not in deletes]
  ops_count['dead_private_store']+=len(deletes)
 # Register value availability across whole CFG. Iterated so removing a load
 # can reveal a later redundant load; semantic transfer for elided loads is no-op.
 for _ in range(5):
  ins,enter=a_must(asm,fn)
  deletes=set()
  for i,(op,arg) in enumerate(ins):
   if op!='lda' or arg not in enter[i][0]:continue
   if enter[i][1]:deletes.add(i)
   else:
    # If next instruction immediately overwrites all NZC flags, it is safe
    # that an elided LDA did not produce a fresh NZ; compare produces C/N/Z.
    nxt=ins[i+1][0] if i+1<len(ins) else None
    if nxt in ('cmp','cpx','cpy'):deletes.add(i)
  if not deletes:break
  asm=[x for i,x in enumerate(asm) if i not in deletes]
  ops_count['elided_redundant_lda']+=len(deletes)
 output.extend(asm)
 res[fn]={'old_lines':ed-st,'new_lines':len(asm)}
(P/'functions.asm').write_text('\n'.join(output)+'\n')
(P/'machine_flow_stats.json').write_text(json.dumps(dict(ops_count,functions=res),indent=2))
print(ops_count)
