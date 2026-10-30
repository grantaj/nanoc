"""Conservative A-register availability at CFG joins.

Baseline machine effects provide a must-agree A snapshot at each tape block
entry. The semantic emitter uses that fact ONLY when a comparison will
immediately overwrite flags, so eliding a redundant LDA cannot change a
flags-dependent branch. This is a two-pass machine-state selection experiment,
not an after-the-fact text peephole pass.
"""
from collections import defaultdict
from state_backend import StateBackend
from tape_frontend import TapeBuilder
from execute6502 import relax
from pathlib import Path

class ABackend(StateBackend):
 def __init__(self,t,arrays=None,enable=True):
    super().__init__(t,arrays,enable=enable)
    self._probe=True
    baseline=super().run()
    self.a_inputs=self.analyse(baseline)
    self.lines=[];self.labels=0;self.current=''
    self._probe=False;self.a_known=set();self.avoided_lda=0
 def simulate(self,lines, initial):
    facts=set(initial)
    for op,arg in lines:
       if op=='label':return set() # internal label, path-dependent A
       if op=='lda':
          facts={arg} if arg.startswith('__v') or arg.startswith('#$') else set()
       elif op=='sta' and arg.startswith('__v'):
          facts.add(arg)
       elif op in ('adc','sbc','and','ora','eor','asl','rol','ror','lsr','pla','txa','tya','tax','jsr'):
          facts.clear()
       elif op in ('inc','dec','rol','asl') and arg.startswith('__v'):
          facts.discard(arg)
    return facts
 def analyse(self,asm):
    bm={b.name:b for b in self.t.blocks if b.name in self.reach}
    pred=defaultdict(set)
    for b in bm.values():
       for nxt in self.succ(b):
          if nxt in bm:pred[nxt].add(b.name)
    ins={n:[] for n in bm};current=None
    for line in asm.splitlines():
       l=line.strip().lower()
       if not l:continue
       if l.endswith(':'):
          n=l[:-1]
          if n in bm:current=n
          elif current is not None:ins[current].append(('label',n))
          continue
       if current is None:continue
       a=l.split(None,1)
       ins[current].append((a[0],a[1] if len(a)>1 else ''))
    old={n:set() for n in bm}
    outgoing={n:set() for n in bm}
    for _ in range(len(bm)*3+3):
       changed=False
       for b in self.t.blocks:
          n=b.name
          if n not in bm:continue
          ps=list(pred[n]);new=set.intersection(*(outgoing[x] for x in ps)) if ps and n!='entry' else set()
          result=self.simulate(ins[n],new)
          if old[n]!=new or outgoing[n]!=result:
             old[n]=new;outgoing[n]=result;changed=True
       if not changed:break
    else:raise RuntimeError('A state must analysis failed')
    return old
 def mark(self,label):
    if not getattr(self,'_probe',True):
       self.a_known=set(self.a_inputs.get(label,())) if label==self.current else set()
    return super().mark(label)
 def emit(self,op,arg=None):
    if getattr(self,'_probe',True):return super().emit(op,arg)
    if op=='lda':
       self.a_known={arg} if arg and (arg.startswith('__v') or arg.startswith('#$')) else set()
    elif op=='sta' and arg and arg.startswith('__v'):
       self.a_known.add(arg)
    elif op in ('adc','sbc','and','ora','eor','asl','rol','ror','lsr','pla','txa','tya','tax','jsr'):
       self.a_known.clear()
    return super().emit(op,arg)
 def compare(self,o,yes,no):
    if getattr(self,'_probe',True):return super().compare(o,yes,no)
    l,r=o.args
    def is_byte(v):
       d=self.defs[v]
       return self.t.values[v] in ('u8','bool') or d.code=='const' and 0<=d.args[0]<=255
    if is_byte(l) and is_byte(r):
       left=self.val(l);right=self.val(r)
       if left in self.a_known:
          # Compare overwrites flags. Suppression is sound ONLY here.
          self.avoided_lda+=1
       else:self.emit('lda',left)
       self.emit('cmp',right)
       c=o.code
       if c=='==':self.emit('beq',yes);self.emit('jmp',no)
       elif c=='!=':self.emit('bne',yes);self.emit('jmp',no)
       elif c=='<':self.emit('bcc',yes);self.emit('jmp',no)
       elif c=='>=':self.emit('bcs',yes);self.emit('jmp',no)
       elif c=='>':self.emit('bcc',no);self.emit('beq',no);self.emit('jmp',yes)
       elif c=='<=':self.emit('bcc',yes);self.emit('beq',yes);self.emit('jmp',no)
       else:raise NotImplementedError(c)
       return
    return super().compare(o,yes,no)

if __name__=='__main__':
 for file in ('parse_atom.c','all_symbols_defined.c','assemble_string.c','scan.c'):
    t=TapeBuilder(Path(file).read_text()).build()
    ar={'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if file=='parse_atom.c' else {'symbol_kind':('u8',896)} if file=='all_symbols_defined.c' else {}
    b=ABackend(t,ar)
    asm,sz,relaxed=relax(b.run())
    Path(file[:-2]+'_areg.asm').write_text(asm)
    print(file,sz,'bytes',b.avoided_lda,'suppressed cmp LDA',len(b.read_alias),'cached reads',len(b.plans),'loop plans')
