"""Research-only last-use direct compare from A for indexed byte reads.

An indexed READ whose sole use is an equality predicate in its own basic
block can feed CMP directly from A. The proof rejects an intervening
machine-emitting operation, an aliased CSE read, a call, or any extra use.
"""
from collections import Counter
from y_loop import YLoopBackend

class DirectReadCompareBackend(YLoopBackend):
    def __init__(self,t,arrays=None,**kwargs):
        super().__init__(t,arrays,**kwargs)
        self.direct_reads={};self.direct_comparisons={}
        self.active_direct_read=None
        self.direct_emitted=0
        self.compute_direct_reads()
    def compute_direct_reads(self):
        uses=Counter()
        for b in self.t.blocks:
            for o in b.ops:
                for v in self.uses(o):
                    if isinstance(v,int) and v in self.defs:uses[v]+=1
        for b in self.t.blocks:
            if b.name not in self.reach:continue
            for ix,o in enumerate(b.ops):
                if o.code!='read' or o.type!='u8' or uses[o.result]!=1 or o.result in self.read_alias or o.result in self.read_alias.values():continue
                tail=b.ops[ix+1:]
                cmp=None
                for item in tail:
                    if item.code in ('const','string','identity'):continue
                    if item.code=='load' and item.result in self.defer:continue
                    if item.code in ('==','!=') and o.result in item.args:
                        cmp=item;break
                    cmp=None;break
                if cmp is None:continue
                lhs,rhs=cmp.args
                other=rhs if lhs==o.result else lhs
                if self.t.values[other] not in ('u8','bool') and not (self.defs[other].code=='const' and 0<=self.defs[other].args[0]<=255):continue
                if not (b.ops[-1].code=='branch' and b.ops[-1].args[0]==cmp.result):continue
                self.direct_reads[o.result]=cmp.result
                self.direct_comparisons[cmp.result]=(o.result,other)
    def emit(self,opcode,arg=None):
        if not getattr(self,'_probe',False) and opcode=='sta' and self.active_direct_read is not None and arg=='__v%d'%self.active_direct_read:
            self.direct_emitted+=1
            return
        return super().emit(opcode,arg)
    def op(self,o):
        if not getattr(self,'_probe',False) and o.code=='read' and o.result in self.direct_reads:
            self.active_direct_read=o.result
            try:return super().op(o)
            finally:self.active_direct_read=None
        return super().op(o)
    def compare(self,o,yes,no):
        if not getattr(self,'_probe',False) and o.result in self.direct_comparisons:
            v,other=self.direct_comparisons[o.result]
            self.emit('cmp',self.val(other))
            self.emit('beq' if o.code=='==' else 'bne',yes)
            self.emit('jmp',no)
            return
        return super().compare(o,yes,no)
