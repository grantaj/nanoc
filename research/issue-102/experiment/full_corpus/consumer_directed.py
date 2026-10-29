"""Producer-to-consumer 6502 selection (research-only).

The existing backend already forwards several ordinary stores and calls.  This
module adds two missing *result location* decisions, made on the typed tape
BEFORE instruction emission, based on single-use and exact effect checks:

* A byte call result whose only observer is a comparison/branch can remain in
  A until the comparison instead of travelling through a private value home.
* A simple arithmetic value used only for immediate return can be returned
  directly in A (byte) or A/X (word), rather than materialising both bytes in
  memory and immediately reloading them.

No function, variable or source-expression spelling is matched. All other
operations fall through to the verified original backend.
"""
from collections import Counter
import os
from compare_native import NativeCompareBackend

class ConsumerDirectedBackend(NativeCompareBackend):
 def __init__(self,t,arrays=None,**kwargs):
  super().__init__(t,arrays,**kwargs)
  self.producer_consumer_stats=Counter()
  self.call_cmp={}
  self.cmp_call={}
  self.return_arith={}
  uses=Counter()
  for b in t.blocks:
   if b.name in self.reach:
    for op in b.ops:
     uses.update(v for v in self.uses(op) if isinstance(v,int) and v in self.defs)
  for b in t.blocks:
   if b.name not in self.reach:continue
   ops=b.ops
   for i,p in enumerate(ops):
    if p.result<0 or uses[p.result]!=1:continue
    # Result of call directly consumed by the branch's comparison, with
    # no intervening operations emitting instructions or modifying A.
    if os.getenv('CONSUMER_CALL','1')=='1' and p.code=='call' and p.type=='u8' and ops[-1].code=='branch':
     cond=self.defs.get(ops[-1].args[0])
     if not cond or cond.code not in ('==','!=','<','<=','>','>=') or p.result not in cond.args:continue
     other=cond.args[1] if cond.args[0]==p.result else cond.args[0]
     if self.defs[other].code not in ('const','load'):continue
     if self.t.values[other] not in ('u8','bool') and not (self.defs[other].code=='const' and 0<=self.defs[other].args[0]<=255):continue
     # Compare code is emitted by the final branch, not the compare Op.
     # All tape operations after the call until that branch must be truly
     # non-emitting (including scalar loads already certified deferred).
     if any(o.code not in ('const','string','identity','low8','high8','load','==','!=','<','<=','>','>=') or
            o.code=='load' and o.result not in self.defer and o.args[0] not in self.arrays or
            o.code in ('==','!=','<','<=','>','>=') and o is not cond
            for o in ops[i+1:-1]):continue
     if self.defs[other].code=='load' and other not in self.defer and self.defs[other].args[0] not in self.arrays:continue
     self.call_cmp[p.result]=cond.result
     self.cmp_call[cond.result]=(p.result,other)
    # Last producer to return value: choose the final register location
    # *before* emitting arithmetic.  Only simple straight-line operations.
    if os.getenv('CONSUMER_RETURN','1')=='1' and p.code in ('+','-','&','|','^','neg') and p.type in ('u8','s16','u16'):
     if i+1>=len(ops) or ops[i+1].code!='return' or ops[i+1].args[0]!=p.result:continue
     if self.width(t.rtype)!=self.width(p.type):continue
     # No multi-instruction shift, multiply, or parent arithmetic sink plan.
     if p.result in getattr(self,'sink_plan',{}):continue
     self.return_arith[p.result]=(p.type,t.rtype)
  self.active_call_cmp=None
  self.active_return_arith=None

 def emit(self,opcode,arg=None):
  if not getattr(self,'_probe',False):
   if self.active_call_cmp is not None and opcode=='sta' and arg=='__v%d'%self.active_call_cmp:
    self.producer_consumer_stats['call_to_compare']+=1
    return
   if self.active_return_arith is not None and opcode=='sta':
    vid,width=self.active_return_arith
    if arg=='__v%d'%vid and width==1:
     self.producer_consumer_stats['byte_arith_to_return']+=1
     return
    if arg=='__v%d+1'%vid and width==2:
     self.producer_consumer_stats['word_high_to_x']+=1
     return super().emit('tax')
  return super().emit(opcode,arg)

 def compare(self,o,yes,no):
  if not getattr(self,'_probe',False) and o.result in self.cmp_call:
   v,other=self.cmp_call[o.result]
   cond=o.code
   if o.args[0]!=v:
    cond={'<':'>','<=':'>=','>':'<','>=':'<=','==':'==','!=':'!='}[cond]
   # A holds exactly the byte returned by the call, after all arg evaluation.
   self.emit('cmp',self.val(other))
   if cond=='==':self.emit('beq',yes);self.emit('jmp',no)
   elif cond=='!=':self.emit('bne',yes);self.emit('jmp',no)
   elif cond=='<':self.emit('bcc',yes);self.emit('jmp',no)
   elif cond=='>=':self.emit('bcs',yes);self.emit('jmp',no)
   elif cond=='>':self.emit('bcc',no);self.emit('beq',no);self.emit('jmp',yes)
   elif cond=='<=':self.emit('bcc',yes);self.emit('beq',yes);self.emit('jmp',no)
   self.producer_consumer_stats['direct_call_compare_branches']+=1
   return
  return super().compare(o,yes,no)

 def op(self,o):
  if getattr(self,'_probe',False):return super().op(o)
  if o.code=='call' and o.result in self.call_cmp:
   self.active_call_cmp=o.result
   try:return super().op(o)
   finally:self.active_call_cmp=None
  if o.result in self.return_arith:
   self.active_return_arith=(o.result,self.width(o.type))
   try:return super().op(o)
   finally:self.active_return_arith=None
  if o.code=='return' and o.args[0] in self.return_arith:
   vid,(p_type,ret_type)=(o.args[0],self.return_arith[o.args[0]])
   if self.width(p_type)==2:
    self.emit('lda','__v%d'%vid)
   self.emit('rts')
   self.producer_consumer_stats['fused_arith_returns']+=1
   return
  return super().op(o)
