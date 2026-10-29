"""Small independent subset-MOS6502 executor for machine-level architecture probe.
Supports exactly the opcodes used by the *experimental* backend. No claim
of VICE, assembler or production 6502 validation.
"""
from pathlib import Path
from subset6502 import parse_lines,BRANCHES
ZP={'__ap','__ap+1','__ix','__ix+1','__rh','__mw','__mw+1'}

def width(op,arg):
 if op in BRANCHES:return 2
 if not arg:return 1
 if arg.startswith('#'):return 2
 if arg.startswith('('):return 2
 if arg in ZP:return 2
 return 3

def relax(source):
 lines=source.splitlines();i=0
 inv={'bcc':'bcs','bcs':'bcc','bne':'beq','beq':'bne','bmi':'bpl','bpl':'bmi','bvs':'bvc','bvc':'bvs'}
 while True:
    pc=0;addresses={};offsets=[]
    for line in lines:
       s=line.strip();offsets.append(pc)
       if s.endswith(':'):addresses[s[:-1].lower()]=pc
       elif s:
          op,*tail=s.lower().split(None,1);pc+=width(op,tail[0] if tail else '')
    for at,line in enumerate(lines):
       s=line.strip().lower();op,*tail=s.split(None,1)
       if op not in BRANCHES:continue
       target=tail[0]
       if target not in addresses:raise ValueError('unresolved branch '+target)
       delta=addresses[target]-(offsets[at]+2)
       if -128<=delta<=127:continue
       if op not in inv:raise ValueError('unrelaxable '+op)
       marker=f'__far_skip_{i}';i+=1
       lines[at:at+1]=[f'    {inv[op]} {marker}',f'    jmp {target}',marker+':']
       break
    else:
       return '\n'.join(lines)+'\n',pc,i
    if i>2000:raise ValueError('branch relax runaway')

class CPU:
 def __init__(self,asm,source,globals_,calls,text_base=0x3000):
    self.ins,self.labels=parse_lines(asm.splitlines())
    self.A=self.X=self.Y=self.C=self.Z=self.N=0
    self.pc=self.labels['entry'];self.steps=0;self.mem={};self.heap={};self.trace=[]
    self.calls=calls;self.invocations={}
    # Label-address layout is synthetic and nonoverlapping.
    self.bases={'text':text_base,'symbol_kind':0x4000,'symbol_payload':0x5000}
    for n,v in globals_.items():
       n=n.lower()
       if n=='text':
          a=self.bases['text'];self.mem[n]=a&255;self.mem[n+'+1']=a>>8
       elif n in ('symbol_kind','symbol_payload'):continue
       elif n in ('VALUE_BAD','VALUE_OK','VALUE_UNRESOLVED','VALUE_SCOPE_ERROR',
                  'VALUE_SYMBOL_FULL','SYMBOL_LABEL_UNDEFINED','atom_used','atom_kind','length','i'):
          self.mem[n]=v&255
       elif n in ('atom_value','atom_symbol','symbol','digit','value'):
          self.mem[n]=v&255;self.mem[n+'+1']=(v>>8)&255
       else:self.mem[n]=v&255;self.mem[n+'+1']=(v>>8)&255
    self.heap.update({self.bases['text']+i:v&255 for i,v in enumerate(source)})
    for n,seq in calls.get('arrays',{}).items():
       base=self.bases[n];w=2 if n=='symbol_payload' else 1
       for j,v in enumerate(seq):
          self.heap[base+j*w]=v&255
          if w==2:self.heap[base+j*w+1]=(v>>8)&255
 def rd(self,arg):
    if arg.startswith('#$'):return int(arg[2:],16)
    if arg.startswith('#<'):return self.bases[arg[2:]]&255
    if arg.startswith('#>'):return self.bases[arg[2:]]>>8
    if arg.endswith(',y') and not arg.startswith('('):
       return self.heap.get((self.bases[arg[:-2]]+self.Y)&65535,0)
    if arg.startswith('(') and arg.endswith('),y'):
       p=arg[1:-3];base=self.mem.get(p,0)+(self.mem.get(p+'+1',0)<<8)
       return self.heap.get((base+self.Y)&65535,0)
    return self.mem.get(arg,0)
 def wr(self,arg,v):
    if arg.endswith(',y') and not arg.startswith('('):
       self.heap[(self.bases[arg[:-2]]+self.Y)&65535]=v&255
    elif arg.startswith('(') and arg.endswith('),y'):
       p=arg[1:-3];base=self.mem.get(p,0)+(self.mem.get(p+'+1',0)<<8)
       self.heap[(base+self.Y)&65535]=v&255
    else:self.mem[arg]=v&255
 def flags(self,v):self.Z=int(v==0);self.N=int(bool(v&128))
 def run(self,max_steps=250000):
    while True:
      if self.steps>=max_steps:raise RuntimeError('6502 exceeded step bound')
      self.steps+=1
      op,arg=self.ins[self.pc];self.trace.append((self.pc,op,arg,self.A,self.X,self.C,self.Z));self.pc+=1
      if op in ('lda','ldx','ldy'):
         v=self.rd(arg)&255
         setattr(self,op[-1].upper(),v);self.flags(v)
      elif op in ('sta','stx','sty'):self.wr(arg,{'sta':self.A,'stx':self.X,'sty':self.Y}[op])
      elif op in ('clc','sec'):self.C=int(op=='sec')
      elif op in ('adc','sbc'):
         v=self.rd(arg)
         if op=='adc':z=self.A+v+self.C;self.C=int(z>255)
         else:z=self.A-v-(1-self.C);self.C=int(z>=0)
         self.A=z&255;self.flags(self.A)
      elif op in ('cmp','cpy'):
         v=self.rd(arg);z=(self.A if op=='cmp' else self.Y)-v
         self.C=int(z>=0);self.flags(z&255)
      elif op in ('and','ora','eor'):
         v=self.rd(arg)
         self.A={'and':lambda:self.A&v,'ora':lambda:self.A|v,'eor':lambda:self.A^v}[op]()
         self.flags(self.A)
      elif op=='asl':
         v=self.A if not arg else self.rd(arg)
         self.C=int(bool(v&128));v=(v<<1)&255
         if not arg:self.A=v
         else:self.wr(arg,v)
         self.flags(v)
      elif op in ('lsr','ror'):
         v=self.A if not arg else self.rd(arg)
         oldcarry=self.C
         self.C=v&1
         n=(v>>1)|((oldcarry<<7) if op=='ror' else 0)
         if not arg:self.A=n
         else:self.wr(arg,n)
         self.flags(n)
      elif op=='rol':
         v=self.A if not arg else self.rd(arg)
         n=((v<<1)|self.C)&255;self.C=int(bool(v&128))
         if not arg:self.A=n
         else:self.wr(arg,n)
         self.flags(n)
      elif op=='tya':self.A=self.Y;self.flags(self.A)
      elif op=='tay':self.Y=self.A;self.flags(self.Y)
      elif op=='tax':self.X=self.A;self.flags(self.X)
      elif op=='txa':self.A=self.X;self.flags(self.A)
      elif op=='iny':self.Y=(self.Y+1)&255;self.flags(self.Y)
      elif op in ('inc','dec'):
         v=(self.rd(arg)+(1 if op=='inc' else -1))&255;self.wr(arg,v);self.flags(v)
      elif op in BRANCHES:
         yes={'bcc':not self.C,'bcs':self.C,'beq':self.Z,'bne':not self.Z,
              'bmi':self.N,'bpl':not self.N,'bvs':False,'bvc':True}[op]
         if yes:self.pc=self.labels[arg]
      elif op=='jmp':self.pc=self.labels[arg]
      elif op=='jsr':
         fn=arg
         self.invocations[fn]=self.invocations.get(fn,0)+1
         if fn=='hex_nibble':
            c=self.mem.get('__call_hex_nibble_0',0)
            val=self.calls[fn](c)&65535
         elif fn in ('find_symbol','intern_label'):
            val=self.calls[fn](self.mem.get('__call_'+fn+'_0',0)+(self.mem.get('__call_'+fn+'_0+1',0)<<8),
                              self.mem.get('__call_'+fn+'_1',0))&65535
         elif fn in self.calls:
            val=self.calls[fn](self.mem.get('__call_'+fn+'_0',0))&65535
         else:raise NotImplementedError('call '+fn)
         # Calls may clobber working registers and scratch pointers.
         self.A=val&255;self.X=val>>8;self.Y=201;self.C=0;self.Z=int(self.A==0)
         for scratch in ZP:self.mem[scratch]=43
      elif op=='rts':return (self.A|self.X<<8),self.mem,self.invocations
      else:raise NotImplementedError((op,arg,self.pc))
