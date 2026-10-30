"""Research: 6502-native word comparisons, without materialised RHS words.

If a bound is a compile-time constant, compare the high byte directly against
an immediate (sign-biasing only for signed ordering) and compare low bytes only
if high bytes are equal. A sign test against zero needs only BMI/BPL. The
fallback is the existing typed comparison for all other forms.
"""
from register_first import RegisterFirstBackend

class NativeCompareBackend(RegisterFirstBackend):
 def __init__(self,t,arrays=None,**kwargs):
  self.native_cmp_count=0;self.native_sign_count=0;self.native_zero_count=0
  super().__init__(t,arrays,**kwargs)
 def compare(self,o,yes,no):
  l,r=o.args
  L,R=self.defs[l],self.defs[r]
  cond=o.code
  kind='u16' if 'u16' in (self.t.values[l],self.t.values[r]) else 's16'
  # Wholly C-pure, so operands can be commuted without changing evaluation.
  if L.code=='const' and R.code!='const':
   l,r=r,l;L,R=R,L
   cond={'<':'>','<=':'>=','>':'<','>=':'<=','==':'==','!=':'!='}[cond]
  if R.code!='const' or L.code=='const':return super().compare(o,yes,no)
  n=R.args[0]&0xffff
  # A byte-to-byte compare has already been optimised by the parent.
  if self.t.values[l] in ('u8','bool') and 0<=n<=255:
   return super().compare(o,yes,no)
  lo,hi=self.val(l),self.val(l,True)
  if n==0 and cond in ('==','!='):
   self.emit('lda',lo);self.emit('ora',hi)
   self.emit('beq' if cond=='==' else 'bne',yes);self.emit('jmp',no)
   self.native_zero_count+=1;return
  # Signed x < 0 or x >= 0 is exactly the 6502 high-byte sign bit.
  if kind=='s16' and ((n==0 and cond in ('<','>=')) or (n==65535 and cond in ('<=','>'))):
   negative=cond in ('<','<=')
   self.emit('lda',hi)
   self.emit('bmi' if negative else 'bpl',yes)
   self.emit('jmp',no)
   self.native_sign_count+=1;return
  # General full-word ordered compare against constant, exact for all 65536 inputs.
  if cond not in ('<','<=','>','>='):return super().compare(o,yes,no)
  nhi=(n>>8)&255
  if kind=='s16':
   self.emit('lda',hi);self.emit('eor','#$80')
   nhi ^= 0x80
  else:self.emit('lda',hi)
  self.emit('cmp','#$%02x'%nhi)
  if cond in ('<','<='):
   self.emit('bcc',yes)
   self.emit('bne',no)
  else:
   self.emit('bcc',no)
   self.emit('bne',yes)
  self.emit('lda',lo)
  self.emit('cmp','#$%02x'%(n&255))
  branches={'<':['bcc'], '<=':['bcc','beq'], '>':['bne'], '>=':['bcs']}
  # For >, BNE is not enough; it is true only if carry is also set.
  if cond=='>':
   self.emit('bcc',no)
   self.emit('beq',no)
   self.emit('jmp',yes)
  elif cond=='<=':
   self.emit('bcc',yes)
   self.emit('beq',yes)
   self.emit('jmp',no)
  else:
   self.emit(branches[cond][0],yes)
   self.emit('jmp',no)
  self.native_cmp_count+=1
