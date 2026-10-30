"""Research-only CFG loop-state planner for an operation tape.

Plans only loops for which an explicit proof establishes a single entry,
unit induction, unchanged bound/base, no calls or indirect writes, and
no interfering zero-page pointer or Y usage. It keeps a zero-page cursor
or a zero-page base+Y cursor across EVERY branch and the loop backedge.

This is a machine-region plan, not a source or function-name recogniser.
All unsupported loops use the existing generic lowering unchanged.
"""
from dataclasses import dataclass
from collections import defaultdict
from backend4 import IndexedBackend
from tape_frontend import TapeBuilder
from execute6502 import relax
from pathlib import Path

@dataclass
class LoopPlan:
    header:str
    entry:str
    latch:str
    induction:str
    initial:int
    bound:str
    base:str
    array:bool
    mode:str   # byte-Y or word-pointer
    reads:set
    nodes:set
    store_index:object
    compare_result:int

class LoopBackend(IndexedBackend):
    def __init__(self,t,arrays=None, enable=True):
        super().__init__(t,arrays)
        self.plans=[];self.rejected=[]
        self.entry_plan={};self.header_plan={};self.latch_plan={};self.read_plan={}
        if enable:self.find_loops()

    def reject(self,header,why):
        self.rejected.append((header,why));return None

    def find_loops(self):
        blocks={b.name:b for b in self.t.blocks if b.name in self.reach}
        preds=defaultdict(set)
        def succ(b):
            term=b.ops[-1]
            if term.code=='jump':return [term.args[0]]
            if term.code=='branch':return list(term.args[1:])
            return []
        for b in blocks.values():
            for name in succ(b):
                if name in blocks:preds[name].add(b.name)
        for hdr in self.t.blocks:
            self.try_candidate(hdr,blocks,preds)

    @staticmethod
    def succ(b):
        term=b.ops[-1]
        if term.code=='jump':return [term.args[0]]
        if term.code=='branch':return list(term.args[1:])
        return []

    def try_candidate(self,hdr,blocks,preds):
        if hdr.name not in blocks or hdr.ops[-1].code!='branch':return
        name=hdr.name
        cond,body,after=hdr.ops[-1].args
        comparison=self.defs.get(cond)
        if comparison is None or comparison.code!='<':return
        lhs,rhs=comparison.args
        ld=self.defs.get(lhs);rd=self.defs.get(rhs)
        if ld is None or ld.code!='load':return
        var=ld.args[0]
        vtype=self.t.types[var]
        if vtype not in ('u8','s16'):return
        if rd is None or rd.code!='load':return self.reject(name,'non-scalar invariant bound')
        bound=rd.args[0]
        if bound==var:return self.reject(name,'self-dependent bound')
        # Follow the entire true-side region, including nested conditionals,
        # stopping only at header, exit, or return. A unique backedge is required.
        loop={name};todo=[body];latches=set();escapes=set()
        while todo:
            node=todo.pop()
            if node in (name,after) or node in loop:continue
            if node not in blocks:return self.reject(name,'unknown successor')
            loop.add(node)
            for nxt in self.succ(blocks[node]):
                if nxt==name:latches.add(node)
                elif nxt==after:escapes.add(node)
                elif nxt not in loop:todo.append(nxt)
        if len(latches)!=1:return self.reject(name,'no unique loop latch')
        latch=next(iter(latches))
        # Valid CFG entry to a natural loop: one preheader and one backedge.
        if len(preds[name])!=2 or latch not in preds[name]:return self.reject(name,'non-canonical header predecessors')
        entry=next(iter(preds[name]-{latch}))
        if blocks[entry].ops[-1].code!='jump' or blocks[entry].ops[-1].args[0]!=name:
            return self.reject(name,'entry is not a dedicated preheader')
        if any(p not in loop for b in loop-{name} for p in preds[b]):
            return self.reject(name,'side entry to loop')
        # Keep the full machine region isolated from other loop plans.
        if any(loop & p.nodes for p in self.plans):return self.reject(name,'overlapping planned loops')
        # The loop must increment exactly once at its unique latch, with
        # no other write to induction, bound, base, indexed memory or calls.
        increments=[];initials=[]
        for o in blocks[entry].ops:
            if o.code=='store' and o.args[0]==var:
                d=self.defs.get(o.args[1]);
                if d and d.code=='const':initials.append(d.args[0])
        if len(initials)!=1 or not (0<=initials[0]<=255):
            return self.reject(name,'nonconstant/out-of-range preheader index')
        for o in blocks[latch].ops:
            if o.code!='store' or o.args[0]!=var:continue
            d=self.defs.get(o.args[1]);
            if d is None or d.code!='+':continue
            a,b=d.args;da,db=self.defs[a],self.defs[b]
            if (da.code=='load' and da.args[0]==var and db.code=='const' and db.args[0]==1):increments.append(o)
        if len(increments)!=1:return self.reject(name,'missing unit step at latch')
        index_store=increments[0]
        reads=[];other_writes=[]
        for bname in loop:
            for o in blocks[bname].ops:
                if o.code in ('call','store_index'):
                    return self.reject(name,'call/indirect write invalidates machine state')
                if o.code=='store':
                    if o is index_store:continue
                    if o.args[0] in (var,bound):return self.reject(name,'induction/bound mutation')
                if o.code=='read':
                    base,index=o.args
                    iddef=self.defs[index]
                    if iddef.code!='load' or iddef.args[0]!=var:
                        return self.reject(name,'multiple indexed expressions would clobber Y/pointer')
                    reads.append(o)
        if not reads:return self.reject(name,'no indexed memory use')
        bases=[]
        for o in reads:
            b=self.defs[o.args[0]]
            if b.code!='load':return self.reject(name,'dynamic pointer expression')
            bases.append(b.args[0])
        if len(set(bases))!=1:return self.reject(name,'distinct pointer/array bases')
        base=bases[0];is_array=base in self.arrays
        if is_array and self.arrays[base][0]!='u8':return self.reject(name,'non-byte elements')
        if not is_array and self.t.types[base]!='ptr':return self.reject(name,'base must be char pointer')
        if any(o.code=='store' and o.args[0]==base for n in loop for o in blocks[n].ops):
            return self.reject(name,'base pointer rebound')
        if any(o.code=='read' and o.type!='u8' for o in reads):
            return self.reject(name,'wide loads not supported')
        # A syntactic load of an array name doesn't fetch a pointer value;
        # reading pointer scalar must be hoisted exactly after the entry.
        mode='byte-Y' if vtype=='u8' and self.t.types[bound]=='u8' else 'word-pointer'
        if mode=='word-pointer' and vtype!='s16':return self.reject(name,'unproved word induction')
        if mode=='word-pointer' and (not is_array or initials[0]!=0):return self.reject(name,'word pointer walk needs zero-based fixed array')
        if mode=='byte-Y' and vtype!='u8':return self.reject(name,'word counter would wrap in Y')
        # Very important: dynamic arithmetic or memory operands may use
        # backend scratch __ap. The only __ap consumers in the loop must
        # be our designated byte reads. Reject any other kind of read.
        plan=LoopPlan(name,entry,latch,var,initials[0],bound,base,is_array,mode,
                    {o.result for o in reads},loop,index_store,cond)
        self.plans.append(plan)
        self.entry_plan[entry]=plan
        self.header_plan[name]=plan
        self.latch_plan[latch]=plan
        for o in reads:self.read_plan[o.result]=plan

    def initialize_state(self,p):
        if p.mode=='byte-Y':
            self.emit('ldy',p.induction)
        else:
            self.emit('ldy','#$00')
        if p.array:
            self.emit('lda','#<'+p.base)
            self.emit('sta','__ap')
            self.emit('lda','#>'+p.base)
            self.emit('sta','__ap+1')
        else:
            self.emit('lda',p.base)
            self.emit('sta','__ap')
            self.emit('lda',p.base+'+1')
            self.emit('sta','__ap+1')

    def op(self,o):
        # Values are already named in the tape: no C spelling-specific rules.
        p=self.entry_plan.get(self.current)
        if o.code=='jump' and p is not None and o.args[0]==p.header:
            self.initialize_state(p)
            return super().op(o)
        p=self.header_plan.get(self.current)
        if p is not None and o.code=='branch' and o.args[0]==p.compare_result and p.mode=='byte-Y':
            # Condition is certified i < scalar_u8_bound. Y mirrors i.
            self.emit('cpy',p.bound)
            self.emit('bcc',o.args[1]);self.emit('jmp',o.args[2]);return
        p=self.read_plan.get(o.result)
        if p is not None and o.code=='read':
            # __ap holds base if using pointer; Y holds induction for byte-Y
            # or zero for a 16-bit pointer-walk indexed from base+current_i.
            self.emit('lda','(__ap),y')
            self.emit('sta','__v%d'%o.result)
            return
        p=self.latch_plan.get(self.current)
        if p is not None and o is p.store_index:
            super().op(o) # exact store via generic emitter/sink
            if p.mode=='byte-Y':
                self.emit('iny')
            else:
                dest=self.fresh()
                self.emit('inc','__ap');self.emit('bne',dest)
                self.emit('inc','__ap+1');self.mark(dest)
            return
        return super().op(o)

if __name__=='__main__':
 for file in ('all_symbols_defined.c','parse_atom.c','assemble_string.c'):
    t=TapeBuilder(Path(__file__).with_name(file).read_text()).build()
    ar={'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if file=='parse_atom.c' else {'symbol_kind':('u8',896)} if file=='all_symbols_defined.c' else {}
    b=LoopBackend(t,ar)
    asm,bytes_,fix=relax(b.run())
    Path(__file__).with_name(file[:-2]+'_loop.asm').write_text(asm)
    print(file,bytes_,'bytes',len(b.plans),'plans', [(p.induction,p.mode,p.base) for p in b.plans], 'rejected',b.rejected)
