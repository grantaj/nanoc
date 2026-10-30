"""Reusable CFG cleanup plus consumer-aware byte store selection on typed tape.
No function or identifier names occur in the lowering rules.
"""
from backend2 import DemandBackend
from tape_frontend import TapeBuilder,Op
from execute6502 import relax
from pathlib import Path
from subset6502 import parse_lines
from collections import Counter


def simplify_cfg(t):
    bm={b.name:b for b in t.blocks}
    def dest(name):
        seen=set()
        while (name in bm and len(bm[name].ops)==1 and bm[name].ops[0].code=='jump'):
            if name in seen:break
            seen.add(name);name=bm[name].ops[0].args[0]
        return name
    old=len(t.blocks)
    for b in t.blocks:
       last=b.ops[-1]
       if last.code=='jump':b.ops[-1]=Op('jump',(dest(last.args[0]),))
       elif last.code=='branch':b.ops[-1]=Op('branch',(last.args[0],dest(last.args[1]),dest(last.args[2])))
    keep=[b for b in t.blocks if b.name=='entry' or not (len(b.ops)==1 and b.ops[0].code=='jump')]
    t.blocks=keep
    return old-len(keep)

class ConsumerBackend(DemandBackend):
 def __init__(self,t,arrays=None):
     self.cfg_shortcuts=simplify_cfg(t)
     super().__init__(t,arrays)
     self.next_label={b.name:(t.blocks[i+1].name if i+1<len(t.blocks) else None) for i,b in enumerate(t.blocks)}
     self.use_counts=Counter()
     for b in t.blocks:
         for o in b.ops:
             self.use_counts.update(v for v in self.uses(o) if isinstance(v,int) and v in self.defs)
     self.sink_plan={}
     self.sink_skipped_loads=set()
     positions={o.result:(b.name,i) for b in t.blocks for i,o in enumerate(b.ops) if o.result>=0}
     for b in t.blocks:
       for i,op in enumerate(b.ops):
         if op.code!='store':continue
         name,v=op.args
         if self.t.types[name]!='u8' or self.use_counts[v]!=1:continue
         sink=self.defs[v]
         if sink.code not in ('+','-'):continue
         lhs,rhs=sink.args;L,R=self.defs[lhs],self.defs[rhs]
         if (L.code=='load' and L.args[0]==name and R.code=='const' and R.args[0]==1):
           mode='inc' if sink.code=='+' else 'dec'
         elif L.code in ('load','const') and R.code in ('load','const'):
           mode='add' if sink.code=='+' else 'sub'
         else:continue
         # A sourced value must be read in order; no named-variable store,
         # unknown memory effect or call between capture and use.
         safe=True
         for x in (lhs,rhs):
           d=self.defs[x]
           if d.code!='load':continue
           loc=positions[x]
           if loc[0]!=b.name:safe=False;break
           for intr in b.ops[loc[1]+1:i]:
             if intr.code in ('call','store_index') or (intr.code=='store' and intr.args[0]==d.args[0]):
               safe=False;break
         if not safe:continue
         self.sink_plan[v]=(name,mode)
         if mode in ('inc','dec') and self.use_counts[lhs]==1:self.sink_skipped_loads.add(lhs)
 def op(self,o):
    c,a,k,d=o.code,o.args,o.type,o.result
    if c=='jump' and a[0]==self.next_label.get(self.current):return
    if c=='load' and d in self.sink_skipped_loads:return
    if c in ('+','-') and d in self.sink_plan:return
    if c=='store' and a[1] in self.sink_plan:
       name,mode=self.sink_plan[a[1]]
       if name!=a[0]:raise RuntimeError('sink mismatch')
       if mode in ('inc','dec'):
          self.emit(mode,name);return
       src=self.defs[a[1]]
       left,right=src.args
       self.emit('lda',self.val(left));self.emit('clc' if mode=='add' else 'sec')
       self.emit('adc' if mode=='add' else 'sbc',self.val(right));self.emit('sta',name)
       return
    return super().op(o)
 def emit_block(self,b):raise RuntimeError('unused')
 def run(self):
    # Override to expose the block name for fallthrough elimination.
    used=set()
    for b in self.t.blocks:
      for o in b.ops:
        if o.code in ('store','return'):args=[o.args[-1]]
        elif o.code=='branch':args=[o.args[0]]
        else:args=[]
        for v in args:
          if isinstance(v,int) and v in self.defs:used.add(v)
    self.demanded_bool={v for v in used if self.defs[v].code in ('==','!=','<','<=','>','>=') and
      any(o.code=='store' and o.args[1]==v or o.code=='return' and o.args[0]==v for b in self.t.blocks for o in b.ops)}
    for b in self.t.blocks:
      if b.name not in self.reach:continue
      self.current=b.name
      self.mark(b.name)
      for o in b.ops:self.op(o)
    return '\n'.join(self.lines)+'\n'

if __name__=='__main__':
 t=TapeBuilder(Path(__file__).with_name('parse_atom.c').read_text()).build()
 b=ConsumerBackend(t,{'symbol_kind':('u8',896),'symbol_payload':('s16',896)})
 asm=b.run();rs,bytes_,fixed=relax(asm)
 Path(__file__).with_name('parse_atom_consumer.asm').write_text(rs)
 print('CFG jump blocks removed',b.cfg_shortcuts,'demand-aware 6502 instructions',len(parse_lines(rs.splitlines())[0]),
       'bytes',bytes_,'far branch repairs',fixed)
 print(Counter(op for op,arg in parse_lines(rs.splitlines())[0]).most_common())
