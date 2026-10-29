from collections import Counter,defaultdict
from pathlib import Path
from large_backend import LargeBackend
from tape_frontend import TapeBuilder
from execute6502 import relax,width
from subset6502 import parse_lines
ROOT=Path(__file__).resolve().parent

def ibytes(lines):
 total=0
 for q in lines:
  s=q.strip()
  if not s or s.endswith(':'):continue
  w=s.split(None,1)
  total+=width(w[0],w[1] if len(w)>1 else '')
 return total

class Instrumented(LargeBackend):
 def __init__(self,*args,**kwargs):
  self.costs=defaultdict(int);self.actions=Counter()
  super().__init__(*args,**kwargs)
  self.costs.clear();self.actions.clear()
 def op(self,o):
  a=len(self.lines)
  super().op(o)
  diff=self.lines[a:]
  n=ibytes(diff)
  self.costs[o.code]+=n
  self.actions[o.code]+=1

for fn,base in [('assemble_instruction',2403),('parse_value',1521),('process_source_line',1624)]:
 t=TapeBuilder((ROOT/(fn+'.c')).read_text()).build();array={'source_line':('u8',256)} if fn=='process_source_line' else {}
 b=Instrumented(t,array);s,n,fix=relax(b.run())
 instructions,_=parse_lines(s.splitlines());counter=Counter(op for op,arg in instructions)
 scratch=[v for v in b.defs if ('__v%d'%v) in s]
 scratch_bytes=sum(1 if t.values[v] in ('u8','bool') else 2 for v in scratch)
 print('\n',fn,'old=',base,'new=',n,'ratio=',round(n/base,3),'blocks=',len(t.blocks),'values=',t.nextvalue,'temps=',len(scratch),'scratch_bytes=',scratch_bytes,'read_alias=',len(b.read_alias),'loopplans=',len(b.plans),'cost_total=',sum(b.costs.values()))
 print('  ops ranked',sorted(b.costs.items(),key=lambda p:-p[1])[:18]);print('  insns',counter.most_common(14));print('  stmts',Counter(o.code for b1 in t.blocks for o in b1.ops))
