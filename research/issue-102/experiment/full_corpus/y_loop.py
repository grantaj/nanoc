"""Research-only proof-driven Y-indexed loop selection for fixed 256-byte scans.

Only a natural 0..255 signed-word loop with a single byte-array index and
unit increment qualifies. Loops with calls, writes, unknown arrays, side
entrances or Y-clobbering operations are rejected. No function names are used.
"""
from collections import defaultdict,Counter
from dataclasses import dataclass
from width_demand import WidthDemandBackend

@dataclass
class YPlan:
    head:str
    pre:str
    latch:str
    body:str
    done:str
    var:str
    reads:set
    returns:set
    suppressed:set

class YLoopBackend(WidthDemandBackend):
    def __init__(self,t,arrays=None,**kwargs):
        super().__init__(t,arrays,**kwargs)
        self.yplans=[];self.y_rejected=[]
        self.plan_by_head={};self.plan_by_pre={};self.plan_by_latch={}
        self.plan_by_op={};self.plan_by_read={};self.plan_by_return={}
        self.plan_y_loops()

    def reject_y(self,head,why):
        self.y_rejected.append((head,why))

    def plan_y_loops(self):
        bm={b.name:b for b in self.t.blocks if b.name in self.reach}
        predecessors=defaultdict(set)
        for b in bm.values():
            for target in self.succ(b):
                if target in bm:predecessors[target].add(b.name)
        for b in bm.values():
            last=b.ops[-1]
            if last.code!='branch':continue
            value,body,done=last.args
            cond=self.defs.get(value)
            if cond is None or cond.code!='<':continue
            left,right=cond.args
            load=self.defs[left];limit=self.defs[right]
            if (load.code!='load' or self.t.values[left]!='s16' or
                limit.code!='const' or limit.args[0]!=256):continue
            var=load.args[0];head=b.name
            # The execution region must have a unique natural backedge and
            # an exclusive preheader. No nested loops or side entrances.
            region={head};todo=[body];latches=set();uncontrolled=False
            while todo:
                node=todo.pop()
                if node==head or node==done or node in region:continue
                if node not in bm:uncontrolled=True;break
                region.add(node)
                for target in self.succ(bm[node]):
                    if target==head:latches.add(node)
                    elif target==done:pass
                    elif target not in region:todo.append(target)
            if uncontrolled or len(latches)!=1:
                self.reject_y(head,'not a unique natural loop');continue
            latch=next(iter(latches))
            if len(predecessors[head])!=2 or latch not in predecessors[head]:
                self.reject_y(head,'noncanonical header edges');continue
            pre=next(iter(predecessors[head]-{latch}))
            if (bm[pre].ops[-1].code!='jump' or bm[pre].ops[-1].args[0]!=head or
                any(pred not in region for n in region-{head} for pred in predecessors[n])):
                self.reject_y(head,'nonexclusive preheader/side entry');continue
            initial=[o for o in bm[pre].ops if o.code=='store' and o.args[0]==var]
            if (len(initial)!=1 or self.defs[initial[0].args[1]].code!='const' or
                self.defs[initial[0].args[1]].args[0]!=0):
                self.reject_y(head,'index not initialized to zero');continue
            # Latch must contain exactly a unit increment plus its jump.
            ops=bm[latch].ops
            writes=[o for o in ops if o.code=='store']
            if len(writes)!=1 or writes[0].args[0]!=var or ops[-1].code!='jump' or ops[-1].args[0]!=head:
                self.reject_y(head,'noncanonical unique increment');continue
            add=self.defs[writes[0].args[1]]
            if add.code!='+' or not (self.defs[add.args[0]].code=='load' and self.defs[add.args[0]].args[0]==var and
                                        self.defs[add.args[1]].code=='const' and self.defs[add.args[1]].args[0]==1):
                self.reject_y(head,'increment is not i=i+1');continue
            suppressed={add.result,add.args[0]}
            seen=set();reads=set();returns=set();valid=True
            for n in region:
                for o in bm[n].ops:
                    if o.code in ('call','store_index','not','neg','<<','>>','*','&','|','^'):
                        valid=False;break
                    if o.code=='store' and (o is not writes[0]):valid=False;break
                    if o.code=='read':
                        base,index=o.args
                        src=self.defs[base];iv=self.defs[index]
                        arr=src.args[0] if src.code=='load' else None
                        if (arr not in self.arrays or self.arrays[arr][0]!='u8' or
                            self.arrays[arr][1]<256 or iv.code!='load' or iv.args[0]!=var or o.type!='u8'):
                            valid=False;break
                        reads.add(o.result);seen.add(index)
                    if o.code=='return':
                        ret=self.defs[o.args[0]]
                        if ret.code=='load' and ret.args[0]==var and self.t.rtype=='s16':
                            returns.add(id(o));seen.add(o.args[0])
                        elif any(self.defs[v].code=='load' and self.defs[v].args[0]==var for v in o.args if isinstance(v,int) and v in self.defs):
                            valid=False;break
                    if o.code in ('<','<=','>','>=','==','!=') and n!=head:
                        if any(self.defs[v].code=='load' and self.defs[v].args[0]==var for v in o.args):
                            valid=False;break
                if not valid:break
            # Only loop header, index reads, early returns, and latch may
            # observe i. No outside reads and no other arithmetic uses.
            if valid:
                uses=defaultdict(list)
                for n in bm:
                    for o in bm[n].ops:
                        for v in self.uses(o):
                            if isinstance(v,int):uses[v].append((n,o))
                for n in bm:
                    for o in bm[n].ops:
                        if o.code=='load' and o.args[0]==var:
                            if n not in region:continue # preheader init is a store; after-loop handled below
                            acceptable=(n==head and o.result==left) or (o.result in seen) or (o.result==add.args[0])
                            if not acceptable:valid=False;break
                    if not valid:break
                # If C observes i after loop, we must materialize 256 there;
                # this first experiment refuses such a live-out.
                if any(o.code=='load' and o.args[0]==var for n in bm if n not in region for o in bm[n].ops):valid=False
            if not valid or not reads:
                self.reject_y(head,'effects, index uses, arrays, or live-out cannot be proven safe');continue
            if any(p in region for p in (set(self.plan_by_head)|set(self.plan_by_latch))):
                self.reject_y(head,'overlapping Y plans');continue
            plan=YPlan(head,pre,latch,body,done,var,reads,returns,suppressed)
            self.yplans.append(plan);self.plan_by_head[head]=plan;self.plan_by_pre[pre]=plan;self.plan_by_latch[latch]=plan
            self.plan_by_read.update({v:plan for v in reads});self.plan_by_return.update({v:plan for v in returns})

    def op(self,o):
        # The superclass performs two-pass A state simulation during __init__.
        # Planned loops are only activated on the final emission pass.
        if getattr(self,'_probe',False) or not hasattr(self,'plan_by_head'):
            return super().op(o)
        pre=self.plan_by_pre.get(self.current)
        if pre and o.code=='jump' and o.args[0]==pre.head:
            self.emit('ldy','#$00')
            return super().op(o)
        plan=self.plan_by_head.get(self.current)
        if plan and o.code=='branch' and o.args[1]==plan.body and o.args[2]==plan.done:
            self.emit('jmp',plan.body);return
        plan=self.plan_by_latch.get(self.current)
        if plan:
            if o.result in plan.suppressed or (o.code=='store' and o.args[0]==plan.var):return
            if o.code=='jump' and o.args[0]==plan.head:
                self.emit('iny');self.emit('bne',plan.head);self.emit('jmp',plan.done);return
        plan=self.plan_by_read.get(o.result)
        if plan and o.code=='read':
            src=self.defs[o.args[0]];arr=src.args[0]
            self.emit('lda',arr+',y');self.emit('sta','__v%d'%o.result)
            return
        if id(o) in self.plan_by_return and o.code=='return':
            self.emit('tya');self.emit('ldx','#$00');self.emit('rts');return
        return super().op(o)
