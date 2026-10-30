from pathlib import Path
import sys,ctypes,random,subprocess
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT))
from execute6502 import CPU
subprocess.run(['cc','-shared','-fPIC','-O0','-funsigned-char','-o',str(ROOT/'oracle_source.so'),str(ROOT/'oracle_source.c')],check=True)
lib=ctypes.CDLL(str(ROOT/'oracle_source.so'))
lib.process_source_line.argtypes=[]
lib.process_source_line.restype=ctypes.c_uint8
src=(ROOT/'process_source_line.asm').read_text()
class TestCPU(CPU):
  def __init__(self,code,arg,env):
    super().__init__(code,arg+b'\0'*8,env,{})
    self.bases['source_line']=0x4000
    self.heap.update({0x4000+i:v for i,v in enumerate(arg)})
  def rd(self,arg):
    if arg=='source_line,y':return self.heap.get((0x4000+self.Y)&65535,0)
    return super().rd(arg)
  def av(self,fn,j,width=1):
    a='__call_'+fn+'_'+str(j)
    return self.mem.get(a,0)+(self.mem.get(a+'+1',0)<<8 if width==2 else 0)
  def hbytes(self,p,n):
    s=0
    for j in range(n):s=((s*33)^self.heap.get((p+j)&65535,0))&65535
    return s
  def log(self,*xs):
    self.ncalls+=1
    for x in xs:self.h=((self.h*33)^(x&65535))&65535
  def run_test(self):
    self.ncalls=self.h=0
    def scan(_):
      st=self.av('scan_argument',0);n=self.mem.get('source_line_length',0)
      self.log(1,st,n,0,0)
      return 0 if st>=n else (0 if self.heap.get(0x4000+st,0)==ord('!') else (n-st)&255)
    def label(_):
      p=self.av('process_label',0,2);n=self.av('process_label',1);h=self.hbytes(p,n)
      self.log(2,n,h,0,0)
      if n and self.heap.get(p,0)==ord('Z') and (p-0x4000)+n+1<self.mem.get('source_line_length',0):
          self.heap[p+n+1]=ord(' ')
      return self.mem.get('assemble_bad_statement',0) if n and self.heap.get(p,0)==ord('E') else self.mem.get('assemble_ok',0)
    def symbol(_):
      p=self.av('process_symbol',0,2);n=self.av('process_symbol',1);a=self.av('process_symbol',2,2);al=self.av('process_symbol',3)
      hp,ha=self.hbytes(p,n),self.hbytes(a,al);self.log(3,n,hp,al,ha);return (n+hp+al+ha)&255
    def direct(_):
      p=self.av('process_instruction_like',0,2);n=self.av('process_instruction_like',1);a=self.av('process_instruction_like',2,2);al=self.av('process_instruction_like',3)
      hp,ha=self.hbytes(p,n),self.hbytes(a,al);self.log(4,n,hp,al,ha);return (n*2+hp+al+ha)&255
    self.calls={'scan_argument':scan,'process_label':label,'process_symbol':symbol,'process_instruction_like':direct}
    r,mem,calls=super().run(100000)
    return r,self.ncalls,self.h
rng=random.Random(2027)
patterns=[b'',b';',b'ABC',b'ABC XY',b'ABC 1',b'ABC: word 5',b'ABC: ',b'ABC = 3',b'E: word 2',b'XXX = !',b'\t ABC:',b'\t\tWORD foo',b'ABC: DEF: word 0',b'Z: foo bar',b'Z: ;',b'Z: word 0',b'ABC\t#1',b'LABEL:word 0',b'ABC : value',b'abc;',b'\t']
for i in range(3500):
    if i < 300: data=patterns[i%len(patterns)]
    else:
        n=rng.randint(0,70)
        data=bytes(rng.choice(b'ABCDEFabcdef  \t\t\t123;=:\n!-') for _ in range(n))
    env={'source_line_length':len(data),'source_line':0x4000,'ASSEMBLE_OK':0,'ASSEMBLE_BAD_STATEMENT':1,'ASSEMBLE_BAD_SYMBOL':2}
    ctypes.c_ubyte.in_dll(lib,'source_line_length').value=len(data)
    arr=(ctypes.c_uint8*256).in_dll(lib,'source_line')
    for j in range(256):arr[j]=data[j] if j<len(data) else 0
    for k,v in env.items():
        if k!='source_line':
            try:ctypes.c_ubyte.in_dll(lib,k).value=v
            except ValueError:pass
    ctypes.c_int.in_dll(lib,'call_count').value=0;ctypes.c_int.in_dll(lib,'call_hash').value=0
    native=lib.process_source_line()
    want=(native,ctypes.c_int.in_dll(lib,'call_count').value,ctypes.c_int.in_dll(lib,'call_hash').value)
    cpu=TestCPU(src,data,env)
    try:got=cpu.run_test()
    except Exception as e:
        print('EXCEPTION',i,data,type(e).__name__,str(e));break
    if tuple(got)!=(tuple(want)):
        print('FAIL',i,data,'got',got,'want',want,'steps',cpu.steps,'trace',cpu.trace[-15:],flush=True);break
else:print('PASS process_source_line 3500 differential cases incl nested labels, delimiters, calls')
