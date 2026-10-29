"""Independent research-only 6502 image encoder for exact Nano C experiment.
Does not replace the real ass.c assembler; the 44 individual functions were
previously assembled and byte-matched by it. Full-image budget can exceed the
real assembler's 11,264-byte staging capacity, hence this independent encoder.
"""
from pathlib import Path
from pycparser import c_parser,c_ast
from collections import defaultdict,Counter
import ast,re,json,struct,sys
R=Path(__file__).parent
SRC=(R/'full_corpus'/'ass.c').read_text()
unit=c_parser.CParser().parse(re.sub(r'/\*.*?\*/','',SRC,flags=re.S))
D={d.name:d for d in unit.ext if isinstance(d,c_ast.Decl)}

def declvalue(x):
 if isinstance(x,c_ast.Constant):
  if x.type=='string':return ast.literal_eval(x.value)
  if x.type=='int':return int(x.value,0)
 raise ValueError(x)
mnems=declvalue(D['mnemonic_table'].init)
mnemonics=[mnems[i:i+3].lower() for i in range(0,171,3)]
mode=[int(x.value) for x in D['opcode_mode'].init.exprs]
mnidx=[int(x.value) for x in D['opcode_mnemonic'].init.exprs]
opcodes=defaultdict(list)
for i in range(256):
 if mode[i]!=13 and mnidx[i]<len(mnemonics):opcodes[(mnemonics[mnidx[i]],mode[i])].append(i)

sym=json.loads((R/'symbols.json').read_text())
for k,v in json.loads((R/'layout.json').read_text())['zp'].items():sym[k]=v
# Runtime ABI, copied from nanoc1/target/runtime.asm (not assuming old unused calls).
for name,addr in [('__nc_io_mode',0xce00),('__nc_io_eof',0xce06),('__nc_io_handle',0xce0c),('__nc_io_name',0xce10),
('__c_io_open__v00',0xcf10),('__c_io_open__v01',0xcf12),('__c_io_read__v00',0xcf14),('__c_io_close__v00',0xcf1e),
('NC_BSS',0x4800),('__nc_bss_bytes',32832),('__experiment_status',0xc83f),('io_open',None),('io_read',None),('io_close',None)]:
 if addr is not None:sym[name]=addr
runtimefiles=R/'runtime'/'nanoc0'/'target'
source=(R/'runtime'/'nanoc1'/'target'/'runtime.asm').read_text()
source=source.split('\tinclude')[0]
source+='\n'+ '\n'.join((runtimefiles/f).read_text() for f in ('io-common.asm','io-open.asm','io-read.asm','io-close.asm'))
# All bare local labels beginning '.' get scoped to the most recent global label,
# reproducing the real assembler's local label addressing semantics.
scoped=[];lastglobal=''
for row in source.splitlines():
 stripped=row.split(';')[0].strip()
 if not stripped:continue
 m=re.match(r'([\w.]+):',stripped)
 if m and not m.group(1).startswith('.'):
  lastglobal=m.group(1)
 def local(mt):return '__local_'+lastglobal+'_'+mt.group()[1:]
 row=re.sub(r'(?<![\w])\.[A-Za-z_][A-Za-z_0-9]*',local,row)
 scoped.append(row)
runtime='\n'.join(scoped)+'\n'
# Bare io_x calls from the research backend should use actual runtime labels.
sym['io_open']='__c_io_open';sym['io_read']='__c_io_read';sym['io_close']='__c_io_close'
# Storage definitions and data.
init=json.loads((R/'initialized.json').read_text())
whole=['* = $0800','    jmp __experiment_entry']
for name,bytes_ in init.items():
 whole.append(name+':')
 for ix in range(0,len(bytes_),16):whole.append('    byte '+','.join(str(v) for v in bytes_[ix:ix+16]))
whole.extend((R/'functions.asm').read_text().splitlines())
whole.extend(runtime.splitlines())
whole.extend((R/'boot.asm').read_text().splitlines())
# Equates are kept away from beginning to prevent confusing label scoping.
# All other local symbols resolved to BSS, including caller parameter aliases.
for name,addr in list(sym.items()):
 if isinstance(addr,str):continue
 whole.append(name+' = $%04x'%addr)
original='\n'.join(whole)+'\n'
(R/'unoptimized.asm').write_text(original)

class Assembler:
 def __init__(self,src,quiet=False):self.src=src;self.quiet=quiet
 def lines(self):
  for ln,n in enumerate(self.src.splitlines(),1):
   s=n.split(';')[0].strip()
   if s:yield ln,s
 def expr(self,a,strict=True):
  a=a.strip()
  lowhigh=None
  if a.startswith(('<','>')):lowhigh,a=a[0],a[1:]
  toks=re.split(r'(?=[+-])',a)
  def atom(v):
   if not v:raise ValueError('empty operand')
   if v.startswith('$'):return int(v[1:],16)
   if v.isdecimal():return int(v)
   if v in self.symbols:
    x=self.symbols[v]
    if isinstance(x,str):return atom(x)
    return x
   if not strict:return 0x5000
   raise KeyError('unresolved '+v)
  val=atom(toks[0]);
  for s in toks[1:]:
   if s.startswith('+'):val+=atom(s[1:])
   elif s.startswith('-'):val-=atom(s[1:])
  if lowhigh=='<':val=val&255
  if lowhigh=='>':val=(val>>8)&255
  return val
 def operand(self,op,a,strict):
  a=a.strip()
  if not a:return (1 if op in ('asl','lsr','rol','ror') else 0),None
  if op in ('bcc','bcs','beq','bne','bmi','bpl','bvc','bvs'):return 12,self.expr(a,strict)
  if a.lower()=='a':return 1,None
  if a.startswith('#'):return 2,self.expr(a[1:],strict)
  if a.startswith('('):
   if a.endswith('),y'):return 11,self.expr(a[1:-3],strict)
   if a.endswith(',x)'):return 10,self.expr(a[1:-3],strict)
   if a.endswith(')'):return 9,self.expr(a[1:-1],strict)
   raise ValueError(('bad indirect',a))
  m=re.fullmatch(r'(.+),([xy])',a)
  suff=m.group(2) if m else None
  value=self.expr(m.group(1) if m else a,strict)
  iszp=value<0x100
  if op in ('jmp','jsr'):
   if suff:raise ValueError('index on jmp/jsr')
   return 6,value
  if suff=='x':return (4 if iszp else 7),value
  if suff=='y':return (5 if iszp else 8),value
  return (3 if iszp else 6),value
 def instruction(self,s,strict):
  op,_,a=s.partition(' ')
  op=op.lower()
  mod,val=self.operand(op,a.strip().replace(',X',',x').replace(',Y',',y'),strict)
  if (op,mod) not in opcodes:
   raise ValueError(f'unknown opcode mode: {op} {a} / mode {mod}')
  octet=opcodes[(op,mod)][0]
  nbytes={0:1,1:1,2:2,3:2,4:2,5:2,6:3,7:3,8:3,9:3,10:2,11:2,12:2}[mod]
  return octet,nbytes,val,mod
 def assemble(self):
  self.symbols=dict(sym);self.symbols.update({'NC_IO_INPUT':1,'NC_IO_OUTPUT':2,'NC_IO_PREFETCH':3,'NC_IO_PREFETCH_EOF':4,
   'NC_IO_HANDLE_COUNT':6,'NC_IO_LFN_BASE':4,'NC_IO_READ_DEVICE':8,'NC_IO_WRITE_DEVICE':9})
  parsed=[]
  for n,s in self.lines():
   if s.startswith('*'):
    v=self.expr(s.split('=')[1],False);parsed.append(('org',n,v));continue
   if '=' in s and not s.startswith(('lda ','cmp ','adc ')) and re.fullmatch(r'\S+\s*=\s*\S+',s):
    k,v=[x.strip() for x in s.split('=',1)];parsed.append(('equ',n,k,v));continue
   if s.endswith(':'):parsed.append(('label',n,s[:-1]));continue
   if s.startswith('byte '):parsed.append(('byte',n,[x.strip() for x in s[5:].split(',')]));continue
   parsed.append(('instr',n,s))
  start=0;final=None
  # Every PC-independent mode is explicit in symbol table except local labels,
  # which cannot be zero-page.  First pass installs unknown labels as non-ZP.
  for typ,n,*arg in parsed:
   if typ=='label':self.symbols[arg[0]]=0x7000
  pc=0
  for typ,n,*args in parsed:
   try:
    if typ=='org':pc=args[0]
    elif typ=='equ':
     k,v=args;self.symbols[k]=self.expr(v,False)
    elif typ=='label':self.symbols[args[0]]=pc
    elif typ=='byte':pc+=len(args[0])
    elif typ=='instr':pc+=self.instruction(args[0],False)[1]
   except Exception as e:raise ValueError((n,args,e)) from e
  # Rewalk until all references known, but widths must stay fixed to preserve
  # addresses; only labels in program region can be forward references.
  output=bytearray();pc=0;counts=Counter();errors=[]
  for typ,n,*args in parsed:
   try:
    if typ=='org':
     pc=args[0];start=pc
    elif typ=='equ':
     k,v=args;self.symbols[k]=self.expr(v,True)
    elif typ=='label':
     assert self.symbols[args[0]]==pc,(n,args[0],self.symbols[args[0]],pc)
    elif typ=='byte':
     for x in args[0]:output.append(self.expr(x,True)&255);pc+=1
    elif typ=='instr':
     op,slen,v,mod=self.instruction(args[0],True)
     counts[args[0].split()[0]]+=1
     output.append(op)
     if slen==2:
      if mod==12:
       delta=v-pc-2
       if not (-128<=delta<=127):raise ValueError(f'branch from {pc:04x} to {v:04x} delta {delta}')
       output.append(delta&255)
      else:output.append(v&255)
     if slen==3:output.extend([v&255,(v>>8)&255])
     pc+=slen
   except Exception as e:raise ValueError((n,args,e)) from e
  return start,bytes(output),self.symbols,counts

if __name__=='__main__':
 a=Assembler(original)
 try:
  start,b,s,c=a.assemble()
 except Exception as e:
  print('ASSEMBLY FAIL',e);raise
 (R/'initial_image.prg').write_bytes(struct.pack('<H',start)+b)
 (R/'resolved.json').write_text(json.dumps(s,indent=2))
 print('IMAGE',hex(start),hex(start+len(b)),len(b),'budget 16384, over=',len(b)-16384,'with BSS base',hex(0x4800))
 print('IO call labels',s['__c_io_open'],s['__c_io_read'],s['__c_io_close'])
 print('instructions',sum(c.values()),'directives data',sum(map(len,init.values())))
