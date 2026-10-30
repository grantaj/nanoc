"""General demand-aware variant for the same typed operation tape.
No source-function-specific code. This tests whether reusable value-demand
and memory-effect rules meaningfully improve the conservative baseline.
"""
from backend import Backend
from collections import defaultdict,Counter
from pathlib import Path
from tape_frontend import TapeBuilder
from subset6502 import parse_lines,ins_size

class DemandBackend(Backend):
 def __init__(self,t,arrays=None):
    super().__init__(t,arrays)
    self.defer=set()
    self.make_deferred()
 def uses(self,o):
    c,a=o.code,o.args
    if c in ('+','-','*','<<','>>','|','&','^','==','!=','<','<=','>','>='):return list(a)
    if c in ('neg','not','return'):return [a[0]]
    if c=='read':return list(a)
    if c=='call':return list(a[1:])
    if c=='store':return [a[1]]
    if c=='store_index':return list(a)
    if c=='branch':return [a[0]]
    return []
 def make_deferred(self):
    # A scalar load can remain a direct memory operand iff no intervening
    # effect can change the snapshot. Cross-block uses would need separate
    # dominance and memory proof; refuse deferral in that case.
    locations={o.result:(b.name,i) for b in self.t.blocks for i,o in enumerate(b.ops) if o.result>=0}
    uses=defaultdict(list)
    for b in self.t.blocks:
      for i,o in enumerate(b.ops):
        for v in self.uses(o):
          if v in locations:uses[v].append((b.name,i))
    for b in self.t.blocks:
      for i,o in enumerate(b.ops):
        if o.code!='load':continue
        name=o.args[0]
        if name in self.arrays:continue
        uc=uses[o.result]
        if not uc or any(nb!=b.name for nb,_ in uc):continue
        last=max(j for _,j in uc)
        # The consuming operation does not occur *between* snapshot and use.
        # In particular, passing a snapshot to a CALL must not make the
        # load eager merely because the consumer is itself effectful.
        between=b.ops[i+1:last]
        # In this C subset, scalar store to another named non-overlapping
        # object does not change a direct scalar load. Calls and pointer
        # stores may change any accessible scalar, so are barriers.
        if any(x.code=='call' or x.code=='store_index' or x.code=='store' and x.args[0]==name for x in between):continue
        self.defer.add(o.result)
 def val(self,v,high=False):
    if v in self.defer:
       src=self.defs[v]
       if self.t.values[v] in ('u8','bool') and high:return '#$00'
       return src.args[0]+('+1' if high else '')
    return super().val(v,high)
 def op(self,o):
    if o.code=='load' and o.result in self.defer:return
    return super().op(o)
 def compare(self,o,yes,no):
    l,r=o.args
    left,right=self.defs[l],self.defs[r]
    def u8_proved(v):
      if self.t.values[v] in ('u8','bool'):return True
      x=self.defs[v]
      return x.code=='const' and 0<=x.args[0]<=255
    if u8_proved(l) and u8_proved(r):
       self.emit('lda',self.val(l));self.emit('cmp',self.val(r))
       cond=o.code
       if cond=='==':self.emit('beq',yes);self.emit('jmp',no)
       elif cond=='!=':self.emit('bne',yes);self.emit('jmp',no)
       elif cond=='<':self.emit('bcc',yes);self.emit('jmp',no)
       elif cond=='>=':self.emit('bcs',yes);self.emit('jmp',no)
       elif cond=='>':
           self.emit('bcc',no);self.emit('beq',no);self.emit('jmp',yes)
       elif cond=='<=':
           self.emit('bcc',yes);self.emit('beq',yes);self.emit('jmp',no)
       return
    return super().compare(o,yes,no)
 def array_ptr(self,base,index):
    # A variable byte index can use (zp),Y and cross pages automatically.
    # However the caller expects the 16-bit address in __ap, so this
    # conservative path remains unchanged: no special scan recognizer.
    return super().array_ptr(base,index)

if __name__=='__main__':
 t=TapeBuilder(Path(__file__).with_name('parse_atom.c').read_text()).build()
 b=DemandBackend(t,{'symbol_kind':('u8',896),'symbol_payload':('s16',896)})
 asm=b.run();Path(__file__).with_name('parse_atom_demand.asm').write_text(asm)
 ins,labs=parse_lines(asm.splitlines());print('DEFERRED',len(b.defer),'loads, code',sum(ins_size(*x) for x in ins),'bytes,',len(ins),'instructions')
 print(Counter(op for op,arg in ins).most_common())
