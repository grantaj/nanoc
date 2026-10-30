"""Experimental must-available memory-value state at arbitrary CFG joins.

Read caching is a second independent machine-state component: it forwards a
value from a previous typed READ when *all incoming paths* have the identical
snapshot, and no possibly-aliasing store/call intervened. There are no source
or function-name patterns, and candidate identities are pointer/array symbol
and variable-index identities, invalidated on writes.
"""
from collections import defaultdict
from loop_backend import LoopBackend
from tape_frontend import TapeBuilder
from pathlib import Path
from execute6502 import relax

class StateBackend(LoopBackend):
 def __init__(self,t,arrays=None,enable=True):
    super().__init__(t,arrays,enable=enable)
    self.read_alias={}
    self.compute_must_reads()
 def read_key(self,o,b=None,index=None):
    baseid,idxid=o.args
    base=self.defs[baseid];idx=self.defs[idxid]
    if base.code!='load':return None
    if idx.code=='load':key=('var',idx.args[0])
    elif idx.code=='const':key=('const',idx.args[0]&65535)
    else:return None
    # A load is an *evaluated snapshot*. Using its variable name as an
    # identity is only sound when the snapshot and READ agree on the
    # current memory version. Require same-block capture and no effects
    # between the capture and the read, or refuse forwarding.
    if b is not None:
       positions={op.result:j for j,op in enumerate(b.ops) if op.result>=0}
       for v in (baseid,idxid):
          d=self.defs[v]
          if d.code!='load':continue
          j=positions.get(v,-1)
          if j<0 or j>=index:return None
          for other in b.ops[j+1:index]:
             if other.code in ('store','call','store_index'):return None
    return (base.args[0],key,o.type)
 def transfer(self,b,mapping,record=False):
    state=dict(mapping)
    for pos,o in enumerate(b.ops):
       if o.code=='read':
          key=self.read_key(o,b,pos)
          if key is None:state.clear();continue
          if key in state:
             if record:self.read_alias[o.result]=state[key]
          else:state[key]=o.result
       elif o.code in ('call','store_index'):
          state.clear()
       elif o.code=='store':
          # All stores potentially alias pointer-derived reads. A known
          # array object itself cannot alias an unrelated scalar variable,
          # but its *index* or base may have changed.
          n=o.args[0]
          state={k:v for k,v in state.items() if
                 k[0] in self.arrays and (k[1][0]!='var' or k[1][1]!=n)}
    return state
 def compute_must_reads(self):
    blocks={b.name:b for b in self.t.blocks if b.name in self.reach}
    pred=defaultdict(set)
    for b in blocks.values():
       for next_ in self.succ(b):
          if next_ in blocks:pred[next_].add(b.name)
    outputs={k:{} for k in blocks}
    inputs={k:{} for k in blocks}
    # Standard forward must analysis: start with no available snapshots.
    # Only data proved on all incoming CFG edges survives a join.
    for it in range(len(blocks)*4+4):
       changed=False
       for b in self.t.blocks:
          name=b.name
          if name not in blocks:continue
          incoming=[outputs[p] for p in pred[name]]
          if name=='entry' or not incoming:inter={}
          else:
             inter=dict(incoming[0])
             for m in incoming[1:]:
                inter={k:v for k,v in inter.items() if m.get(k)==v}
          out=self.transfer(b,inter)
          if out!=outputs[name] or inter!=inputs[name]:
             inputs[name]=inter;outputs[name]=out;changed=True
       if not changed:break
    else:raise RuntimeError('must-analysis did not converge')
    self.read_alias={}
    for b in self.t.blocks:
       if b.name in self.reach:self.transfer(b,inputs[b.name],record=True)
    self.must_in=inputs
 def val(self,v,high=False):
    if v in self.read_alias:
       return super().val(self.read_alias[v],high)
    return super().val(v,high)
 def op(self,o):
    if o.code=='read' and o.result in self.read_alias:return
    return super().op(o)

if __name__=='__main__':
 for file in ('all_symbols_defined.c','parse_atom.c','assemble_string.c'):
    t=TapeBuilder(Path(__file__).with_name(file).read_text()).build()
    ar={'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if file=='parse_atom.c' else {'symbol_kind':('u8',896)} if file=='all_symbols_defined.c' else {}
    b=StateBackend(t,ar)
    asm,sz,nrelax=relax(b.run())
    Path(__file__).with_name(file[:-2]+'_state.asm').write_text(asm)
    print(file,'bytes',sz,'cached reads',len(b.read_alias),'planned loops',[(p.induction,p.mode) for p in b.plans])
