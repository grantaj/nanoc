"""Research-only two-pointer byte scanner using persistent ZP pointer bases.

Recognise a certified natural loop with 8-bit unit induction, a stable byte
bound, and two *read-only* pointer bases. Keep both pointers in __ap/__ix and
index in Y across loop blocks. Scalar index is still physically incremented
so pointer-to-index aliases observe the same memory semantics as the C source.
No function-name matching or speculative pointer alias disambiguation.
"""
from dataclasses import dataclass
from collections import defaultdict
from read_compare import DirectReadCompareBackend

@dataclass
class DualPlan:
    pre:str
    hdr:str
    latch:str
    index:str
    bound:str
    bases:tuple
    nodes:set
    reads:dict
    compare_id:int
    store:object

class DualPointerBackend(DirectReadCompareBackend):
    def __init__(self,t,arrays=None,**kwargs):
        super().__init__(t,arrays,**kwargs)
        self.dual_plans=[];self.dual_pre={};self.dual_hdr={};self.dual_latch={};self.dual_reads={}
        self.dual_rejected=[]
        self.find_dual_loops()

    def find_dual_loops(self):
        bm={b.name:b for b in self.t.blocks if b.name in self.reach}
        preds=defaultdict(set)
        for b in bm.values():
            for d in self.succ(b):
                if d in bm:preds[d].add(b.name)
        for head in bm.values():
            last=head.ops[-1]
            if last.code!='branch':continue
            cmp=self.defs.get(last.args[0])
            if not cmp or cmp.code!='<':continue
            lhs,rhs=cmp.args;l=self.defs[lhs];r=self.defs[rhs]
            if not (l.code=='load' and r.code=='load' and self.t.values[lhs]=='u8' and self.t.values[rhs]=='u8'):
                continue
            index,bound=l.args[0],r.args[0]
            reg={head.name};todo=[last.args[1]];latches=set();invalid=False
            while todo:
                n=todo.pop()
                if n in (head.name,last.args[2]) or n in reg:continue
                if n not in bm:invalid=True;break
                reg.add(n)
                for d in self.succ(bm[n]):
                    if d==head.name:latches.add(n)
                    elif d!=last.args[2]:todo.append(d)
            if invalid or len(latches)!=1:continue
            latch=next(iter(latches))
            if len(preds[head.name])!=2 or latch not in preds[head.name]:continue
            pre=next(iter(preds[head.name]-{latch}))
            if (bm[pre].ops[-1].code!='jump' or bm[pre].ops[-1].args[0]!=head.name or
                any(p not in reg for n in reg-{head.name} for p in preds[n])):continue
            init=[o for o in bm[pre].ops if o.code=='store' and o.args[0]==index]
            if len(init)!=1:continue
            src_init=self.defs[init[0].args[1]]
            if src_init.code!='const' or not(0<=src_init.args[0]<=255):continue
            changes=[o for n in reg for o in bm[n].ops if o.code=='store']
            latchstore=[o for o in changes if o.args[0]==index]
            if len(latchstore)!=1 or bm[latch].ops[-1].code!='jump' or bm[latch].ops[-1].args[0]!=head.name:continue
            add=self.defs[latchstore[0].args[1]]
            if not (add.code=='+' and self.defs[add.args[0]].code=='load' and self.defs[add.args[0]].args[0]==index and
                    self.defs[add.args[1]].code=='const' and self.defs[add.args[1]].args[0]==1):continue
            if any(o.args[0] in (index,bound) and o is not latchstore[0] for o in changes):continue
            reads={};bases=set();safe=True
            for n in reg:
                for o in bm[n].ops:
                    if o.code in ('call','store_index'):safe=False;break
                    if o.code=='read':
                        src=self.defs[o.args[0]];ix=self.defs[o.args[1]]
                        if (src.code!='load' or self.t.values[o.args[0]]!='ptr' or ix.code!='load' or ix.args[0]!=index or o.type!='u8'):
                            safe=False;break
                        bases.add(src.args[0]);reads[o.result]=src.args[0]
                    if o.code in ('*','<<','>>','&','|','^','neg','not'):
                        safe=False;break
                    if o.code in ('+','-') and o is not add:
                        # Other arithmetic could generate Y/indexed accesses.
                        safe=False;break
                if not safe:break
            if not safe or len(bases)!=2 or any(p.nodes & reg for p in self.dual_plans) or any(p.nodes & reg for p in self.yplans):continue
            if any(o.code=='store' and o.args[0] in bases for n in reg for o in bm[n].ops):continue
            # The two ZP pointers can safely survive all intervening ops:
            # reads use our own plan; no effectful calls, indirect stores, or
            # other address formation remains in the loop.
            # A return of index uses its updated physical byte cell.
            p=DualPlan(pre,head.name,latch,index,bound,tuple(sorted(bases)),reg,reads,last.args[0],latchstore[0])
            self.dual_plans.append(p);self.dual_pre[pre]=p;self.dual_hdr[head.name]=p;self.dual_latch[latch]=p
            self.dual_reads.update({v:p for v in reads})

    def op(self,o):
        if getattr(self,'_probe',False) or not hasattr(self,'dual_pre'):
            return super().op(o)
        p=self.dual_pre.get(self.current)
        if p and o.code=='jump' and o.args[0]==p.hdr:
            self.emit('ldy',p.index)
            for base,ptr in zip(p.bases,('__ap','__ix')):
                self.emit('lda',base);self.emit('sta',ptr)
                self.emit('lda',base+'+1');self.emit('sta',ptr+'+1')
            return super().op(o)
        p=self.dual_hdr.get(self.current)
        if p and o.code=='branch' and o.args[0]==p.compare_id:
            self.emit('cpy',p.bound);self.emit('bcc',o.args[1]);self.emit('jmp',o.args[2]);return
        p=self.dual_reads.get(o.result)
        if p and o.code=='read':
            name=p.reads[o.result]
            z='__ap' if name==p.bases[0] else '__ix'
            self.emit('lda','('+z+'),y')
            if o.result not in self.direct_reads:self.emit('sta','__v%d'%o.result)
            return
        p=self.dual_latch.get(self.current)
        if p and o is p.store:
            super().op(o)
            self.emit('iny')
            return
        return super().op(o)
