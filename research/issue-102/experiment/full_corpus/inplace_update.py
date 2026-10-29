"""Experiment: select an in-place 6502 update at the typed store consumer.

Only matches a same-block, single-use, effect-free expression of the form
    target = target +/- 1;
It does not turn generic arithmetic into an unsafe RMW, and refuses if the
store destination or source types disagree or an intervening side effect occurs.
"""
from collections import Counter
from compare_native import NativeCompareBackend

class InplaceUpdateBackend(NativeCompareBackend):
    def __init__(self,t,arrays=None,**kwargs):
        super().__init__(t,arrays,**kwargs)
        counts=Counter()
        for b in t.blocks:
            for o in b.ops:
                for v in self.uses(o):
                    if isinstance(v,int) and v in self.defs:counts[v]+=1
        self.inplace={};self.inplace_sources=set();self.inplace_stats=Counter()
        for b in t.blocks:
            if b.name in self.plan_by_latch or b.name in self.dual_latch:
                continue  # preserve Y-carried loop induction machine trajectories
            ops=b.ops
            for ix,o in enumerate(ops):
                if o.code!='store':continue
                dest,vid=o.args
                if self.t.types[dest] not in ('s16','u16'):continue
                val=self.defs[vid]
                if val.code not in ('+','-') or counts[vid]!=1:continue
                a,bv=val.args
                da,db=self.defs[a],self.defs[bv]
                if da.code!='load' or da.args[0]!=dest or db.code!='const':continue
                if val.code=='+' and (db.args[0]&65535)!=1:continue
                if val.code=='-' and (db.args[0]&65535)!=1:continue
                # Must be same block; no intervening writes or calls from the
                # source load through the expression and final assignment.
                def position(v):
                    for j,q in enumerate(ops[:ix]):
                        if q.result==v:return j
                    return -1
                ai=position(a);vi=position(vid)
                if ai<0 or vi<ai or vi>=ix:continue
                if any(x.code in ('store','store_index','call') for x in ops[ai+1:ix]):continue
                # Another semantic user of the original result is forbidden.
                if counts[a]!=1:continue
                # A separate placement could skip the store, but we own both.
                self.inplace[id(o)]=(dest,val.code,self.t.types[dest])
                self.inplace_sources.add(vid)
                self.inplace_stats[(val.code,self.t.types[dest])]+=1
    def op(self,o):
        if not getattr(self,'_probe',False):
            if o.result in self.inplace_sources:return
            plan=self.inplace.get(id(o))
            if plan is not None:
                dest,action,kind=plan
                ins='inc' if action=='+' else 'dec'
                if action=='+':
                    self.emit('inc',dest)
                    lab=self.fresh()
                    self.emit('bne',lab)
                    self.emit('inc',dest+'+1')
                    self.mark(lab)
                else:
                    lab=self.fresh()
                    self.emit('lda',dest)
                    self.emit('bne',lab)
                    self.emit('dec',dest+'+1')
                    self.mark(lab)
                    self.emit('dec',dest)
                return
        return super().op(o)
