"""Research-only consumer-location planner: compare direct destination fusion
against whole-CFG machine-state tracking. Never select by function name.
Only an immediate, single-use value may be forwarded; uses, widths, and
memory effects are checked before choosing a storage location.
"""
from collections import Counter
from large_backend import LargeBackend
from backend4 import IndexedBackend

class PlacementMixin:
    def plan_placements(self, enable=True):
        self.sinks={};self.skipped=set();self.forwarded=Counter()
        if not enable:return
        counts=Counter()
        for b in self.t.blocks:
            for op in b.ops:
                c,a=op.code,op.args
                if c in ('return','branch'): vs=a[:1]
                elif c=='call':vs=a[1:]
                elif c=='store':vs=a[1:]
                elif c in ('+','-','*','<<','>>','|','&','^','==','!=','<','<=','>','>=','read'):vs=a
                elif c in ('neg','not'):vs=a
                else:vs=()
                for v in vs:
                    if isinstance(v,int) and v in self.defs:counts[v]+=1
        # Only one-use, adjacent producer->consumer is eligible. This is a
        # bounded *lifetime proof*, not a source-text or named-function rule.
        for b in self.t.blocks:
            for i,o in enumerate(b.ops[:-1]):
                v=o.result
                if v<0 or counts[v]!=1:continue
                next_=b.ops[i+1]
                if next_.code=='store' and next_.args[1]==v:
                    name=next_.args[0]
                    # Safe class: full-width identical copies, or byte producer
                    # to byte consumer. Avoid pointer/word aliasing surprises.
                    if self.t.types[name]!=o.type:continue
                    if o.code not in ('call','read','+','-','neg','not'):continue
                    if o.code=='read' and v in getattr(self,'read_alias',{}):continue
                    if o.code in ('+','-') and v in getattr(self,'sink_plan',{}):continue
                    if o.code in ('+','-'):
                        # A computation writing its destination can mutate an
                        # input still needed, especially a deferred source.
                        if any(self.defs[z].code=='load' and self.defs[z].args[0]==name for z in o.args):continue
                    self.sinks[v]=('store',name)
                    self.skipped.add(id(next_))
                    self.forwarded['store_'+o.code]+=1
                elif (next_.code=='return' and next_.args[0]==v and o.code=='call' and
                      self.width(self.t.rtype)==self.width(o.type)):
                    self.sinks[v]=('return',None)
                    self.skipped.add(id(next_))
                    self.forwarded['return_call']+=1
    def __init__(self,*args,enable_placement=True,**kwargs):
        super().__init__(*args,**kwargs)
        self.plan_placements(enable_placement)
        self.placement_active=None
    def emit(self,opcode,arg=None):
        plan=getattr(self,'placement_active',None)
        if plan is not None and arg is not None and opcode in ('sta','stx'):
            v, mode, dest=plan
            stem='__v'+str(v)
            if arg==stem or arg==stem+'+1':
                if mode=='return':return
                arg=dest+('+1' if arg.endswith('+1') else '')
        return super().emit(opcode,arg)
    def op(self,o):
        if not getattr(self,'_probe',False):
            if id(o) in self.skipped:return
            if o.result in self.sinks:
                mode,dest=self.sinks[o.result]
                self.placement_active=(o.result,mode,dest)
                try:
                    super().op(o)
                finally:
                    self.placement_active=None
                if mode=='return':
                    # Byte-return ABI: A is the entire result, X is caller-clobbered.
                    self.emit('rts')
                return
        return super().op(o)

class PlacementBackend(PlacementMixin,LargeBackend):pass
# Alternative simpler architecture without whole-CFG machine-state dataflow:
class LocalPlacementBackend(PlacementMixin,IndexedBackend):
    def val(self,v,high=False):
        d=self.defs[v]
        if d.code=='load' and d.args[0] in self.arrays:
            return ('#>' if high else '#<')+d.args[0]
        return super().val(v,high)

class CallArgumentMixin:
    """Choose the ABI argument slot as the initial location of a one-use
    byte/word result. This is an alternative to allocating an IR temporary.
    Valid only for a same-block, effect-free producer-to-call region.
    """
    def __init__(self,*args,enable_args=True,**kwargs):
        super().__init__(*args,**kwargs)
        self.arg_targets={};self.active_call=None
        self.arg_counts=Counter()
        if not enable_args:return
        counts=Counter()
        for b in self.t.blocks:
            for op in b.ops:
                if op.code=='call':vs=op.args[1:]
                elif op.code in ('return','branch'):vs=op.args[:1]
                elif op.code=='store':vs=op.args[1:]
                elif op.code in ('+','-','*','<<','>>','|','&','^','==','!=','<','<=','>','>=','read','neg','not'):vs=op.args
                else:vs=()
                for v in vs:
                    if isinstance(v,int) and v in self.defs:counts[v]+=1
        for b in self.t.blocks:
            where={o.result:i for i,o in enumerate(b.ops) if o.result>=0}
            for i,call in enumerate(b.ops):
                if call.code!='call':continue
                fn=call.args[0]
                for j,v in enumerate(call.args[1:]):
                    if counts[v]!=1 or v in self.sinks or v in getattr(self,'read_alias',{}):continue
                    if self.width(self.t.call_params[fn][j])!=self.width(self.t.values[v]):continue
                    prod=self.defs[v];start=where.get(v,-1)
                    if start<0 or start>=i:continue
                    if prod.code not in ('read','+','-'):continue
                    # No effect or external call may intervene. The static
                    # private parameter slot cannot be observed from C here.
                    if any(o.code in ('call','store','store_index') for o in b.ops[start+1:i]):continue
                    if prod.code in ('+','-') and v in getattr(self,'sink_plan',{}):continue
                    dest='__call_'+fn+'_'+str(j)
                    self.arg_targets[v]=dest
                    self.arg_counts[prod.code]+=1
    def emit(self,opcode,arg=None):
        if not getattr(self,'_probe',False) and arg is not None and opcode in ('sta','stx'):
            import re
            m=re.fullmatch(r'__v(\d+)(\+1)?',arg)
            if m:
                v=int(m.group(1));dest=self.arg_targets.get(v)
                if dest is not None:arg=dest+(m.group(2) or '')
        return super().emit(opcode,arg)
    def copy_val(self,v,dest,k):
        if not getattr(self,'_probe',False) and self.arg_targets.get(v)==dest and self.active_call is not None:
            return
        return super().copy_val(v,dest,k)
    def op(self,o):
        if not getattr(self,'_probe',False) and o.code=='call':
            self.active_call=o.args[0]
            try:return super().op(o)
            finally:self.active_call=None
        return super().op(o)

class ArgumentPlacementBackend(CallArgumentMixin,PlacementBackend):pass
class LocalArgumentBackend(CallArgumentMixin,LocalPlacementBackend):pass
