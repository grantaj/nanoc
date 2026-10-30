from pathlib import Path
import sys,ctypes,random,subprocess
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT))
from execute6502 import CPU
subprocess.run(['cc','-shared','-fPIC','-O0','-funsigned-char','-o',str(ROOT/'oracle_assemble.so'),str(ROOT/'oracle_assemble.c')],check=True)
lib=ctypes.CDLL(str(ROOT/'oracle_assemble.so'))
lib.assemble_instruction.argtypes=[ctypes.c_void_p,ctypes.c_uint8,ctypes.c_void_p,ctypes.c_uint8]
lib.assemble_instruction.restype=ctypes.c_uint8
src=(ROOT/'assemble_instruction.asm').read_text()
class TestCPU(CPU):
  def __init__(self,code,arg,name,env):
    self.input_arg=arg;self.input_name=name
    super().__init__(code,arg+b'\0'*4,env,{'name':None})
    self.bases['argument']=0x3000;self.bases['name']=0x6000
    self.heap.update({0x3000+i:x for i,x in enumerate(arg)})
    self.heap.update({0x6000+i:x for i,x in enumerate(name)})
  def argval(self,fn,j,width):
    a='__call_'+fn+'_'+str(j)
    v=self.mem.get(a,0)
    if width==2:v|=(self.mem.get(a+'+1',0)<<8)
    return v
  def data(self,ptr,n):return [self.heap.get((ptr+i)&65535,0) for i in range(n)]
  def hashbytes(self,ptr,n):
    s=0
    for c in self.data(ptr,n):s=((s*33)^c)&65535
    return s
  def log(self,tag,a,b,c,d):
    self.count+=1
    for v in (tag,a,b,c,d):self.hashv=((self.hashv*33)^(v&65535))&65535
  def run_test(self):
    self.count=0;self.hashv=0
    def find_mnemonic(_):
        p=self.argval('find_mnemonic',0,2);n=self.argval('find_mnemonic',1,1);s=self.hashbytes(p,n)
        self.log(1,n,s,0,0);return 65535 if n==0 or s%11==0 else s%56
    def find_opcode(_):
        m=self.argval('find_opcode',0,1);mode=self.argval('find_opcode',1,1)
        self.log(2,m,mode,0,0);return 65535 if (m+mode)%4==0 else (m*3+mode)&255
    def upper_char(_):
        c=self.argval('upper_char',0,1)
        self.log(3,c,0,0,0);return c-32 if 97<=c<=122 else c
    def stage(_):
        op=self.argval('stage_resolved_instruction',0,2);mode=self.argval('stage_resolved_instruction',1,1);val=self.argval('stage_resolved_instruction',2,2)
        self.log(4,op,mode,val,0);return (op+mode+val+21)&255
    def mode(_):
        m=self.argval('assemble_mode_value',0,1);mo=self.argval('assemble_mode_value',1,1);p=self.argval('assemble_mode_value',2,2);n=self.argval('assemble_mode_value',3,1);s=self.hashbytes(p,n)
        self.log(5,m,mo,n,s);return (m+mo+n+s)&255
    def direct(_):
        m=self.argval('assemble_direct_value',0,1);p=self.argval('assemble_direct_value',1,2);n=self.argval('assemble_direct_value',2,1);ix=self.argval('assemble_direct_value',3,1);s=self.hashbytes(p,n)
        self.log(6,m,n,ix,s);return (m+n+ix+s)&255
    self.calls={k:v for k,v in locals().items() if k in ('find_mnemonic','find_opcode','upper_char')}
    self.calls.update({'stage_resolved_instruction':stage,'assemble_mode_value':mode,'assemble_direct_value':direct})
    got,mem,inv=super().run(100000)
    return got,self.count,self.hashv
rng=random.Random(42)
for i in range(1500):
    n=rng.randint(0,16);na=rng.randint(0,5)
    cases=[b'',b'A',b'a',b'XY',b'#1',b'(9),Y',b'(1,X)',b'($fff)',b'$ffff,X',b'$ab,Y',b'   ',b'()','abc'.encode()]
    arg=cases[i%len(cases)] if i<240 else bytes(rng.choice(b'A#(),$ 1xY9b2') for _ in range(n))
    name=bytes(rng.choice(b'ABCXYZabc') for _ in range(na))
    env={'name':0x6000,'argument':0x3000,'name_length':len(name),'argument_length':len(arg),'ASSEMBLE_BAD_INSTRUCTION':5,
     'MODE_IMPLIED':0,'MODE_ACCUMULATOR':1,'MODE_IMMEDIATE':2,'MODE_INDIRECT_Y':11,'MODE_INDIRECT_X':10,'MODE_INDIRECT':9}
    for k,v in env.items():
        try:ctypes.c_ubyte.in_dll(lib,k).value=v
        except ValueError:pass
    ctypes.c_int.in_dll(lib,'calls').value=0;ctypes.c_int.in_dll(lib,'hashvalue').value=0
    native=lib.assemble_instruction(ctypes.c_char_p(name+b'\0'),len(name),ctypes.c_char_p(arg+b'\0'),len(arg))
    cpu=TestCPU(src,arg,name,env)
    got,ncalls,h=cpu.run_test()
    expected_calls=ctypes.c_int.in_dll(lib,'calls').value
    expected_hash=ctypes.c_int.in_dll(lib,'hashvalue').value
    if (got&255,ncalls,h)!=(native,expected_calls,expected_hash):
        print('FAIL case',i, 'name',name,'arg',arg,'got',(got&255,ncalls,h),'want',(native,expected_calls,expected_hash),'steps',cpu.steps,flush=True)
        print('trace',cpu.trace[-15:]);break
else:print('PASS assemble_instruction 1500 differential cases with call argument hashes')
