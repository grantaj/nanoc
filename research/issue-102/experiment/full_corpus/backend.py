"""General conservative 6502 lowering of the typed operation tape.
This is an intentionally SIMPLE reference backend: eager snapshots and fixed
static value slots guarantee correct sequencing, but may be expensive.
No function-name rules; all operation kinds generic. Meant to falsify the
assumption that a tape alone produces good machine code.
"""
from tape_frontend import TapeBuilder
from collections import Counter

class Backend:
 def __init__(self,t,arrays=None):
    self.t=t;self.arrays=arrays or {}
    self.lines=[];self.code='';self.current='';self.labels=0
    self.defs={o.result:o for b in t.blocks for o in b.ops if o.result>=0}
    self.reach=self.reachable()
 def reachable(self):
    targets={'entry'}
    changed=True
    bmap={b.name:b for b in self.t.blocks}
    while changed:
      n=len(targets)
      for x in list(targets):
        op=bmap[x].ops[-1]
        if op.code=='branch':targets.update(op.args[1:])
        if op.code=='jump':targets.add(op.args[0])
      changed=len(targets)>n
    return targets
 def fresh(self):self.labels+=1;return '__sel'+str(self.labels)
 def emit(self,op,arg=None):self.lines.append('    '+op+(' '+str(arg) if arg is not None else ''))
 def mark(self,label):self.lines.append(label+':')
 def val(self,v,high=False):
    src=self.defs[v]
    if src.code=='string':return ('#>' if high else '#<')+src.args[0]
    if src.code=='const':
      return '#$%02x'%(((src.args[0]&65535)>>(8 if high else 0))&255)
    if self.t.values[v] in ('u8','bool') and high:return '#$00'
    return '__v%d'%v+('+1' if high else '')
 def copy_val(self,v,dest,k):
    self.emit('lda',self.val(v));self.emit('sta',dest)
    if k in ('u16','s16','ptr'):
      self.emit('lda',self.val(v,True));self.emit('sta',dest+'+1')
 def width(self,typ):return 1 if typ in ('u8','bool') else 2
 def addr(self,v,arr):
    # Evaluate the *full 16-bit C address* and any size-based scaling.
    typ=self.t.values[v];elem=self.arrays.get(arr,('u8',0))[0]
    if arr in self.arrays:
       self.emit('lda','#<'+arr);self.emit('sta','__ap')
       self.emit('lda','#>'+arr);self.emit('sta','__ap+1')
    else:
       self.emit('lda',self.val(v));self.emit('sta','__ap')
       self.emit('lda',self.val(v,True));self.emit('sta','__ap+1')
 def array_ptr(self,base,index):
    b=self.defs[base]
    arr=b.args[0] if b.code=='load' and b.args[0] in self.arrays else None
    element=self.arrays[arr][0] if arr else 'u8'
    if arr:
       self.emit('lda','#<'+arr);self.emit('sta','__ap')
       self.emit('lda','#>'+arr);self.emit('sta','__ap+1')
    else:
       self.emit('lda',self.val(base));self.emit('sta','__ap')
       self.emit('lda',self.val(base,True));self.emit('sta','__ap+1')
    # Compute index bytes. Word array indexes scale by 2.
    if element in ('u16','s16'):
       self.emit('lda',self.val(index));self.emit('asl');self.emit('sta','__ix')
       self.emit('lda',self.val(index,True));self.emit('rol');self.emit('sta','__ix+1')
    else:
       self.emit('lda',self.val(index));self.emit('sta','__ix')
       self.emit('lda',self.val(index,True));self.emit('sta','__ix+1')
    self.emit('clc');self.emit('lda','__ap');self.emit('adc','__ix');self.emit('sta','__ap')
    self.emit('lda','__ap+1');self.emit('adc','__ix+1');self.emit('sta','__ap+1')
    return element
 def compare(self,o,yes,no):
    l,r=o.args;kind='u16' if 'u16' in (self.t.values[l],self.t.values[r]) else 's16'
    # comparison of u8 promoted to s16 is correct via zero extension.
    lowL,highL=self.val(l),self.val(l,True)
    lowR,highR=self.val(r),self.val(r,True)
    false=no;true=yes
    # Equality: high then low, both 16-bit regardless of operand type
    if o.code in ('==','!='):
       diff=true if o.code=='!=' else false
       equal=true if o.code=='==' else false
       self.emit('lda',highL);self.emit('cmp',highR);self.emit('bne',diff)
       self.emit('lda',lowL);self.emit('cmp',lowR)
       self.emit('beq',equal);self.emit('jmp',diff)
       return
    # High-byte signed comparisons via sign flip, no overflow assumptions.
    if kind=='s16':
       self.emit('lda',highR);self.emit('eor','#$80');self.emit('sta','__rh')
       highR='__rh'
       self.emit('lda',highL);self.emit('eor','#$80')
    else:self.emit('lda',highL)
    self.emit('cmp',highR)
    lt,gt,eq=self.fresh(),self.fresh(),self.fresh()
    self.emit('bcc',lt);self.emit('bne',gt)
    self.emit('lda',lowL);self.emit('cmp',lowR)
    self.emit('bcc',lt);self.emit('bne',gt);self.emit('jmp',eq)
    targets={'<':(true,false,false),'<=':(true,false,true),'>':(false,true,false),'>=':(false,true,true)}
    mapped=targets[o.code]
    for label,target in zip((lt,gt,eq),mapped):
       self.mark(label);self.emit('jmp',target)
 def materialize_bool(self,o):
    yes,no=self.fresh(),self.fresh();done=self.fresh()
    self.compare(o,yes,no)
    self.mark(yes);self.emit('lda','#$01');self.emit('jmp',done)
    self.mark(no);self.emit('lda','#$00')
    self.mark(done);self.emit('sta','__v%d'%o.result)
 def arith(self,o):
    a,b=o.args;target='__v%d'%o.result;typ=o.type
    if o.code in ('&','|','^') and self.defs[b].code=='const' and (self.defs[b].args[0]&65535)==65535:
        if o.code=='&':return self.copy_val(a,target,typ)
    if o.code=='>>' and self.defs[b].code=='const':
        n=self.defs[b].args[0]
        if n>=16:
           if self.t.values[a]=='s16':raise NotImplementedError('signed right shift by >=16')
           self.emit('lda','#$00');self.emit('sta',target);self.emit('sta',target+'+1');return
        self.copy_val(a,target,'u16')
        for _ in range(n):
           if self.t.values[a]=='s16':
               self.emit('lda',target+'+1');self.emit('cmp','#$80');self.emit('ror');self.emit('sta',target+'+1')
           else:self.emit('lsr',target+'+1')
           self.emit('ror',target)
        return
    if o.code=='<<' and self.defs[b].code=='const':
        n=self.defs[b].args[0]
        if n>=16:
           self.emit('lda','#$00');self.emit('sta',target);self.emit('sta',target+'+1');return
        self.copy_val(a,target,typ)
        for _ in range(n):
          self.emit('asl',target);self.emit('rol',target+'+1')
        return
    if o.code=='*' and self.defs[b].code=='const':
        n=self.defs[b].args[0]&65535
        if n not in range(0,256):raise NotImplementedError('dynamic or wide multiply')
        # General shift-add constant multiplier. Multiply modulo 2**16.
        self.emit('lda','#$00');self.emit('sta',target);self.emit('sta',target+'+1')
        self.copy_val(a,'__mw','u16')
        for bit in range(8):
          if (n>>bit)&1:
             self.emit('clc');self.emit('lda',target);self.emit('adc','__mw');self.emit('sta',target)
             self.emit('lda',target+'+1');self.emit('adc','__mw+1');self.emit('sta',target+'+1')
          if bit<7 and (n>>(bit+1)):
             self.emit('asl','__mw');self.emit('rol','__mw+1')
        return
    if o.code not in ('+','-','&','|','^'):raise NotImplementedError('arith '+o.code)
    self.emit('lda',self.val(a))
    if o.code in ('+','-'):self.emit('clc' if o.code=='+' else 'sec')
    self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[o.code],self.val(b))
    self.emit('sta',target)
    if self.width(typ)==2:
        self.emit('lda',self.val(a,True))
        self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[o.code],self.val(b,True))
        self.emit('sta',target+'+1')
 def op(self,o):
    c,a,k,d=o.code,o.args,o.type,o.result
    if c in ('const','string'):return
    if c=='load':
       name=a[0]
       if name in self.arrays:return
       self.emit('lda',name);self.emit('sta','__v%d'%d)
       if self.width(k)==2:
         self.emit('lda',name+'+1');self.emit('sta','__v%d+1'%d)
    elif c=='read':
       base,index=a;element=self.array_ptr(base,index)
       self.emit('ldy','#$00');self.emit('lda','(__ap),y');self.emit('sta','__v%d'%d)
       if self.width(k)==2:
         self.emit('iny');self.emit('lda','(__ap),y');self.emit('sta','__v%d+1'%d)
    elif c=='store_index':
       base,index,value=a
       parent=self.defs[base]
       arr=parent.args[0] if parent.code=='load' and parent.args[0] in self.arrays else None
       element=self.arrays[arr][0] if arr else 'u8'
       offset=self.defs[index]
       narrow=(self.t.values[index] in ('u8','bool') or offset.code=='const' and 0<=offset.args[0]<=255)
       if narrow and element=='u8':
           self.emit('ldy',self.val(index))
           if arr:self.emit('lda',self.val(value));self.emit('sta',arr+',y')
           else:
               self.emit('lda',self.val(base));self.emit('sta','__ap')
               self.emit('lda',self.val(base,True));self.emit('sta','__ap+1')
               self.emit('lda',self.val(value));self.emit('sta','(__ap),y')
       else:
           self.array_ptr(base,index)
           self.emit('ldy','#$00');self.emit('lda',self.val(value));self.emit('sta','(__ap),y')
           if element!='u8':
               self.emit('iny');self.emit('lda',self.val(value,True));self.emit('sta','(__ap),y')
    elif c=='call':
       fn,*args=a
       for j,v in enumerate(args):
         dest='__call_'+fn+'_'+str(j)
         # The callee's declared parameter type determines the ABI slot
         # width, not the source expression type. This performs C's
         # implicit char/word conversion at the call boundary.
         param_kind=self.t.call_params[fn][j]
         self.copy_val(v,dest,param_kind)
       self.emit('jsr',fn);self.emit('sta','__v%d'%d)
       if self.width(k)==2:self.emit('stx','__v%d+1'%d)
    elif c=='store':self.copy_val(a[1],a[0],self.t.types[a[0]])
    elif c=='neg':
       self.emit('sec');self.emit('lda','#$00');self.emit('sbc',self.val(a[0]));self.emit('sta','__v%d'%d)
       self.emit('lda','#$00');self.emit('sbc',self.val(a[0],True));self.emit('sta','__v%d+1'%d)
    elif c=='not':
       self.emit('lda',self.val(a[0]));self.emit('ora',self.val(a[0],True))
       no=self.fresh();done=self.fresh();self.emit('bne',no)
       self.emit('lda','#$01');self.emit('jmp',done);self.mark(no);self.emit('lda','#$00');self.mark(done);self.emit('sta','__v%d'%d)
    elif c in ('+','-','*','<<','>>','&','|','^'):self.arith(o)
    elif c in ('==','!=','<','<=','>','>='):
       # Only compute boolean if it is demanded as a stored value.
       if d in self.demanded_bool:self.materialize_bool(o)
    elif c=='branch':
       cmp=self.defs[a[0]]
       if cmp.code in ('==','!=','<','<=','>','>='):
          self.compare(cmp,a[1],a[2])
       else:
          self.emit('lda',self.val(a[0]));self.emit('ora',self.val(a[0],True))
          self.emit('bne',a[1]);self.emit('jmp',a[2])
    elif c=='jump':self.emit('jmp',a[0])
    elif c=='return':
       self.emit('lda',self.val(a[0]));
       if self.width(self.t.rtype)==2:self.emit('ldx',self.val(a[0],True))
       # A-only ABI for u8 functions; any wide consumer obtains zero-extension
       # from its typed call result, never from an unspecified X register.
       self.emit('rts')
    else:raise NotImplementedError('op '+c)
 def run(self):
    used=set()
    for b in self.t.blocks:
      for o in b.ops:
        if o.code in ('store','return'):args=[o.args[-1]]
        elif o.code=='branch':args=[o.args[0]]
        else:args=[]
        for v in args:
          if isinstance(v,int) and v in self.defs:used.add(v)
    self.demanded_bool={v for v in used if self.defs[v].code in ('==','!=','<','<=','>','>=') and
         any(o.code=='store' and o.args[1]==v or o.code=='return' and o.args[0]==v for b in self.t.blocks for o in b.ops)}
    for block in self.t.blocks:
       if block.name not in self.reach:continue
       self.mark(block.name)
       for o in block.ops:self.op(o)
    return '\n'.join(self.lines)+'\n'

if __name__=='__main__':
 from pathlib import Path
 t=TapeBuilder(Path(__file__).with_name('parse_atom.c').read_text()).build()
 b=Backend(t,{'symbol_kind':('u8',896),'symbol_payload':('s16',896)})
 asm=b.run();Path(__file__).with_name('parse_atom_naive.asm').write_text(asm)
 from collections import Counter
 from subset6502 import parse_lines,ins_size
 ins,labels=parse_lines(asm.splitlines())
 print('assembled mnemonic count',len(ins),'instruction byte estimate',sum(ins_size(*x) for x in ins))
 print(Counter(op for op,arg in ins).most_common())
