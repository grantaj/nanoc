"""Experiment: exact-width operation tape simplification, not source-name patterns.

The C front-end has already chosen 16-bit Nano C types.  A 16-bit value
masked with 0xffff is unchanged, masking with 0xff is a low-byte view,
and shifting an unsigned 16-bit value eight places then masking to one
byte is a high-byte view.  No machine instructions are required to form
such a view; only consumers determine whether it needs storage.
"""
from collections import Counter
from tape_frontend import Op,TapeBuilder
from placement_backend import ArgumentPlacementBackend

PURE={'load','const','string','+','-','*','<<','>>','&','|','^',
      '==','!=','<','<=','>','>=','read','neg','not','identity','low8','high8'}


def transform(t):
    defs={o.result:o for b in t.blocks for o in b.ops if o.result>=0}
    n=Counter()
    for b in t.blocks:
      for j,o in enumerate(b.ops):
        if o.code=='&':
          a,v=o.args
          right=defs.get(v)
          if right and right.code=='const':
            mask=right.args[0]&0xffff
            if mask==0xffff:
              b.ops[j]=Op('identity',(a,),o.type,o.result);n['identity']+=1
            elif mask==255:
              d=defs.get(a)
              if d and d.code=='>>':
                word,shift=d.args
                cnt=defs.get(shift)
                if cnt and cnt.code=='const' and cnt.args[0]==8 and t.values[word] in ('s16','u16','ptr'):
                  b.ops[j]=Op('high8',(word,),o.type,o.result);n['high8']+=1;continue
              b.ops[j]=Op('low8',(a,),o.type,o.result);n['low8']+=1
    # Recompute all demands AFTER rewriting the dependent value operation.
    defs={o.result:o for b in t.blocks for o in b.ops if o.result>=0}
    wanted=set()
    def uses(o):
      if o.code in ('return','branch','neg','not','identity','low8','high8'):return o.args[:1]
      if o.code=='call':return o.args[1:]
      if o.code=='store':return o.args[1:]
      if o.code=='store_index':return o.args
      if o.code in ('read','+','-','*','<<','>>','|','&','^','==','!=','<','<=','>','>='):return o.args
      return ()
    work=[]
    for b in t.blocks:
      for o in b.ops:
        if o.code not in PURE:
          work.extend(v for v in uses(o) if isinstance(v,int) and v in defs)
    while work:
      v=work.pop()
      if v in wanted:continue
      wanted.add(v)
      work.extend(x for x in uses(defs[v]) if isinstance(x,int) and x in defs)
    for b in t.blocks:
      filtered=[]
      for o in b.ops:
        if o.result>=0 and o.code in PURE and o.result not in wanted:
           n['removed_dead_pure']+=1
           continue
        filtered.append(o)
      b.ops=filtered
    return n

class ByteDemandBackend(ArgumentPlacementBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.byte_plan=transform(t)
        super().__init__(t,arrays,**kwargs)
    def uses(self,o):
        if o.code in ('identity','low8','high8'):return [o.args[0]]
        return super().uses(o)
    def val(self,v,high=False):
        o=self.defs[v]
        if o.code=='identity':return self.val(o.args[0],high)
        if o.code=='low8':return '#$00' if high else self.val(o.args[0])
        if o.code=='high8':return '#$00' if high else self.val(o.args[0],True)
        return super().val(v,high)
    def compare(self,o,yes,no):
        left,right=o.args
        # Byte comparisons already choose the processor flags directly.
        def byte(v):
            d=self.defs[v]
            return self.t.values[v] in ('u8','bool') or d.code=='const' and 0<=d.args[0]<=255
        if (byte(left) and byte(right)) or o.code in ('==','!='):
            return super().compare(o,yes,no)
        # General word ordering: compare high bytes first. If they match,
        # compare low bytes. Branch directly to the two semantic successors.
        lh,rh=self.val(left,True),self.val(right,True)
        if 'u16' not in (self.t.values[left],self.t.values[right]):
            if rh.startswith('#$'):
                rh='#$%02x'%(int(rh[2:],16)^0x80)
            else:
                self.emit('lda',rh);self.emit('eor','#$80');self.emit('sta','__rh')
                rh='__rh'
            if lh.startswith('#$'):
                self.emit('lda','#$%02x'%(int(lh[2:],16)^0x80))
            else:
                self.emit('lda',lh);self.emit('eor','#$80')
        else:self.emit('lda',lh)
        self.emit('cmp',rh)
        if o.code in ('<','<='):
            self.emit('bcc',yes)
            self.emit('bne',no)
        else:
            self.emit('bcc',no)
            self.emit('bne',yes)
        self.emit('lda',self.val(left));self.emit('cmp',self.val(right))
        if o.code=='<':
            self.emit('bcc',yes);self.emit('jmp',no)
        elif o.code=='<=':
            self.emit('bcc',yes);self.emit('beq',yes);self.emit('jmp',no)
        elif o.code=='>':
            self.emit('bcc',no);self.emit('beq',no);self.emit('jmp',yes)
        elif o.code=='>=':
            self.emit('bcs',yes);self.emit('jmp',no)
        else:raise NotImplementedError(o.code)
    def op(self,o):
        if o.code in ('identity','low8','high8'):return
        if o.code=='store':
            target,v=o.args
            src=self.defs.get(v)
            if src and src.code=='identity':
                underlying=self.defs.get(src.args[0])
                if underlying and underlying.code=='load' and underlying.args[0]==target:
                    # No volatile objects in Phase 1.  The identity has no
                    # effects; its source load and store have no intervening
                    # effect, as demanded by the tape's statement order.
                    return
        return super().op(o)
