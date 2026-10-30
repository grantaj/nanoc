"""Independent byte-level MOS 6502 execution of the *linked binary*.
Research oracle only: KERNAL disk calls are deterministic device-8 traps;
not VICE and not a hardware/cycle-accurate emulator.
"""
from pathlib import Path
import sys,re,ctypes,random,time
from build_image import mnemonics,mode,mnidx,R
from pycparser import c_parser
import json
BIN=R/'compact_image.prg';SYM=json.loads((R/'compact_resolved.json').read_text())
START=int.from_bytes(BIN.read_bytes()[:2],'little');CODE=BIN.read_bytes()[2:]
OPS={i:(mnemonics[mnidx[i]],mode[i]) for i in range(256) if mode[i]!=13 and mnidx[i]<len(mnemonics)}
BRANCH={'bcc':lambda c:not c.C,'bcs':lambda c:c.C,'beq':lambda c:c.Z,'bne':lambda c:not c.Z,
'bmi':lambda c:c.N,'bpl':lambda c:not c.N,'bvc':lambda c:not c.V,'bvs':lambda c:c.V}
class Machine:
 def __init__(self,files):
  self.m=bytearray(65536);self.m[START:START+len(CODE)]=CODE
  self.m[1]=0x37;self.A=self.X=self.Y=self.C=self.N=self.Z=self.V=0
  self.PC=START;self.SP=0xff;self.cycles=0;self.calls={};self.trace=[]
  self.fn_bytes={name.lower():v.replace(b'\n',b'\r') for name,v in files.items()}
  self.filedesc={};self.io_name=b'';self.io_lfn=0;self.io_device=8;self.io_current=None;self.io_status=0
  self.open_names=[]
 def read(self,a):
  a&=0xffff
  if 0xa000<=a<=0xbfff and (self.m[1]&3)==3:raise RuntimeError(f'BASIC ROM mapped while reading RAM at {a:04x} PC={self.PC:04x}')
  if 0xd000<=a<=0xdfff:raise RuntimeError('unexpected I/O read '+hex(a))
  return self.m[a]
 def write(self,a,v):self.m[a&0xffff]=v&255
 def word(self,a):return self.read(a)|(self.read((a+1)&0xffff)<<8)
 def poke_word(self,a,v):self.write(a,v);self.write(a+1,v>>8)
 def zpword(self,a):return self.read(a)|(self.read((a+1)&255)<<8)
 def fetch(self):v=self.read(self.PC);self.PC=(self.PC+1)&65535;return v
 def fetchword(self):v=self.fetch();return v|(self.fetch()<<8)
 def zn(self,v):self.Z=int((v&255)==0);self.N=int(bool(v&0x80))
 def push(self,v):self.write(0x100+self.SP,v);self.SP=(self.SP-1)&255
 def pop(self):self.SP=(self.SP+1)&255;return self.read(0x100+self.SP)
 def kernal(self,a):
  # All operations use the published jump-table entry ABI, but I/O is host
  # emulation, not actual ROM implementation.
  self.calls[a]=self.calls.get(a,0)+1
  if a==0xffcc: # CLRCHN
   self.io_current=None;return
  if a==0xffbd: # SETNAM len A, pointer X:Y
   self.io_name=bytes(self.read((self.X|(self.Y<<8))+i) for i in range(self.A))
   return
  if a==0xffba: # SETLFS lfn A device X secondary Y
   self.io_lfn=self.A;self.io_device=self.X;return
  if a==0xffc0: # OPEN
   key=self.io_name.decode('latin1').lower();self.open_names.append(key)
   if self.io_device!=8 or key not in self.fn_bytes:
    self.C=1;return
   self.filedesc[self.io_lfn]={'text':self.fn_bytes[key],'pos':0}
   self.C=0;return
  if a==0xffc6: # CHKIN lfn X
   self.C=int(self.X not in self.filedesc)
   if not self.C:self.io_current=self.X
   return
  if a==0xffcf: # CHRIN
   if self.io_current not in self.filedesc:raise RuntimeError('CHRIN no file')
   f=self.filedesc[self.io_current];pos=f['pos'];s=f['text']
   if pos>=len(s):self.io_status=0x40;self.A=0
   else:
    self.A=s[pos];f['pos']=pos+1;self.io_status=0x40 if f['pos']==len(s) else 0
   self.zn(self.A);return
  if a==0xffb7: # READST
   self.A=self.io_status;self.zn(self.A);return
  if a==0xffc3: # CLOSE lfn A
   self.filedesc.pop(self.A,None);self.C=0;return
  raise NotImplementedError('KERNAL JSR $%04x'%a)
 def operand(self,mod):
  if mod==0:return None,None
  if mod==1:return None,self.A
  if mod==2:return None,self.fetch()
  if mod==3:
   a=self.fetch();return a,self.read(a)
  if mod==4:
   a=(self.fetch()+self.X)&255;return a,self.read(a)
  if mod==5:
   a=(self.fetch()+self.Y)&255;return a,self.read(a)
  if mod in (6,7,8):
   a=self.fetchword()
   if mod==7:a=(a+self.X)&65535
   if mod==8:a=(a+self.Y)&65535
   return a,self.read(a)
  if mod==9:
   a=self.fetchword();t=self.read(a)|(self.read((a&0xff00)|((a+1)&255))<<8)
   return t,None
  if mod==10:
   a=(self.fetch()+self.X)&255;a=self.zpword(a);return a,self.read(a)
  if mod==11:
   a=self.zpword(self.fetch());a=(a+self.Y)&65535;return a,self.read(a)
  if mod==12:
   d=self.fetch();return (self.PC+(d if d<128 else d-256))&65535,None
  raise NotImplementedError(mod)
 def step(self):
  oldpc=self.PC;opcode=self.fetch()
  if opcode not in OPS:raise RuntimeError(f'illegal opcode ${opcode:02x} at {oldpc:04x}')
  op,mod=OPS[opcode]
  # JSR may be a KERNAL trap and must not resolve/read the target as data.
  if op=='jsr':
   target=self.fetchword()
   if target>=0xff00:
    self.kernal(target);return
   ret=(self.PC-1)&65535;self.push(ret>>8);self.push(ret&255);self.PC=target;return
  if op=='rts':self.PC=(self.pop()|(self.pop()<<8))+1;self.PC&=65535;return
  if op=='jmp':target,_=self.operand(mod);self.PC=target;return
  if op in BRANCH:
   target,_=self.operand(mod)
   if BRANCH[op](self):self.PC=target
   return
  if op=='clc':self.C=0;return
  if op=='sec':self.C=1;return
  if op=='cld':return
  if op=='php':
   self.push((self.N<<7)|(self.V<<6)|0x30|(self.Z<<1)|self.C);return
  if op=='plp':
   ps=self.pop();self.N=(ps>>7)&1;self.V=(ps>>6)&1;self.Z=(ps>>1)&1;self.C=ps&1;return
  if op=='tax':self.X=self.A;self.zn(self.X);return
  if op=='tay':self.Y=self.A;self.zn(self.Y);return
  if op=='txa':self.A=self.X;self.zn(self.A);return
  if op=='tya':self.A=self.Y;self.zn(self.A);return
  if op=='dex':self.X=(self.X-1)&255;self.zn(self.X);return
  if op=='dey':self.Y=(self.Y-1)&255;self.zn(self.Y);return
  if op=='inx':self.X=(self.X+1)&255;self.zn(self.X);return
  if op=='iny':self.Y=(self.Y+1)&255;self.zn(self.Y);return
  addr,v=self.operand(mod)
  if op=='lda':self.A=v;self.zn(v);return
  if op=='ldx':self.X=v;self.zn(v);return
  if op=='ldy':self.Y=v;self.zn(v);return
  if op in ('sta','stx','sty'):
   self.write(addr,{'sta':self.A,'stx':self.X,'sty':self.Y}[op]);return
  if op in ('cmp','cpx','cpy'):
   left={'cmp':self.A,'cpx':self.X,'cpy':self.Y}[op]
   d=left-v;self.C=int(d>=0);self.zn(d);return
  if op in ('ora','and','eor'):
   self.A={'ora':self.A|v,'and':self.A&v,'eor':self.A^v}[op];self.zn(self.A);return
  if op in ('adc','sbc'):
   if op=='adc':r=self.A+v+self.C;self.V=int(bool((~(self.A^v)&(self.A^r))&0x80));self.C=int(r>255)
   else:r=self.A-v-(1-self.C);self.V=int(bool(((self.A^v)&(self.A^r))&0x80));self.C=int(r>=0)
   self.A=r&255;self.zn(self.A);return
  if op in ('asl','lsr','rol','ror'):
   n=self.A if mod==1 else v
   if op=='asl':self.C=(n>>7)&1;out=(n<<1)&255
   elif op=='lsr':self.C=n&1;out=n>>1
   elif op=='rol':carry=self.C;self.C=(n>>7)&1;out=((n<<1)|carry)&255
   else:carry=self.C;self.C=n&1;out=(n>>1)|(carry<<7)
   if mod==1:self.A=out
   else:self.write(addr,out)
   self.zn(out);return
  if op in ('inc','dec'):
   out=(v+ (1 if op=='inc' else -1))&255;self.write(addr,out);self.zn(out);return
  raise NotImplementedError((op,mod,hex(oldpc)))
 def run(self,max_steps=4000000):
  stop=SYM['__experiment_stop'];start=time.time()
  for it in range(max_steps):
   if self.PC==stop:return it,round(time.time()-start,2)
   try:self.step()
   except Exception as e:
    print('CRASH at',hex(self.PC),'after',it,'instructions', 'registers',self.A,self.X,self.Y,self.C,self.Z,self.N,'SP',hex(self.SP),'IO',self.open_names)
    raise
  raise RuntimeError(f'timeout after {max_steps} instructions PC={self.PC:04x} stack {self.SP:02x} open={self.open_names}')

def run_oracle(source):
 lib=ctypes.CDLL(str(R/'full_corpus'/'host_ass.so'))
 # Existing adapter C uses lowercase filenames case sensitive; use temp test.
 path=R/'test.asm';path.write_bytes(source)
 try:
  lib.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
  lib.ass_assemble.restype=ctypes.c_ubyte
  ret=lib.ass_assemble(str(path).encode(),len(str(path)),b'',0,0)
  n=ctypes.c_int.in_dll(lib,'ass_image_length').value
  raw=bytes((ctypes.c_ubyte*11264).in_dll(lib,'ass_image'))[:n]
  return ret,raw
 finally:path.unlink(missing_ok=True)
if __name__=='__main__':
 cases={
 'minimal':b'* = $0800\nlda #$12\nsta $c000\n',
 'data':b'* = $0800\nbyte 1,2,3,4\nword $1234, $f00d\n',
 'labels':b'* = $0800\nstart: lda #1\nbeq done\nlda #2\ndone: rts\n',
 'symbol':b'* = $0800\nnumber = $1234\nword number\n',
 }
 for name,source in cases.items():
  cpu=Machine({'test.asm':source})
  try:steps,seconds=cpu.run()
  except Exception as e:
   print('FAILED',name,str(e));raise
  status=cpu.m[SYM['__experiment_status']]
  act_len=cpu.word(SYM['ass_image_length']);actual=bytes(cpu.m[SYM['ass_image']:SYM['ass_image']+act_len])
  expect_code,expected=run_oracle(source)
  print(name,'steps',steps,'time',seconds,'status',status,'expect status',expect_code,'lengths',act_len,len(expected),'match',actual==expected, 'opened',cpu.open_names)
  if actual!=expected or status!=expect_code:print('got',actual[:64].hex(),'expect',expected[:64].hex());raise AssertionError(name)
