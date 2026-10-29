from pathlib import Path
import sys,ctypes,random,subprocess
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT))
from execute6502 import CPU
subprocess.run(['cc','-shared','-fPIC','-O0','-funsigned-char','-o',str(ROOT/'oracle_parse.so'),str(ROOT/'oracle_parse.c')],check=True)
lib=ctypes.CDLL(str(ROOT/'oracle_parse.so'))
lib.parse_value.argtypes=[ctypes.c_void_p,ctypes.c_uint8]
lib.parse_value.restype=ctypes.c_uint8
src=(ROOT/'parse_value.asm').read_text()
const={'VALUE_BAD':1,'VALUE_OK':0,'VALUE_UNRESOLVED':2,'VALUE_PREFIX_LOW':1,'VALUE_PREFIX_HIGH':2,'VALUE_PREFIX_NONE':0}
class TestCPU(CPU):
  def __init__(self,code,arg,env):
    super().__init__(code,arg+b'\0'*4,env,{})
    self.bases['text']=0x3000
  def av(self,fn,j,width=1):
    a='__call_'+fn+'_'+str(j)
    return self.mem.get(a,0)+(self.mem.get(a+'+1',0)<<8 if width==2 else 0)
  def run_test(self):
    self.pcalls=self.prefix_calls=self.parse_hash=0
    def atom(_):
      p=self.av('parse_atom',0,2);n=self.av('parse_atom',1);x=[];s=0
      for j in range(n):
        v=self.heap.get((p+j)&65535,0)
        if v in (43,45):break
        s=((s*33)^v)&65535;x.append(v)
      used=len(x)
      self.pcalls+=1;self.parse_hash=((self.parse_hash*33)^s)&65535
      self.mem['atom_used']=used;self.mem['atom_kind']=0
      self.mem['atom_value']=(s*7+used*13)&255;self.mem['atom_value+1']=((s*7+used*13)>>8)&255
      self.mem['atom_symbol']=s&255;self.mem['atom_symbol+1']=0
      if not used or x[0]==ord('?'):return 1
      if x[0]==ord('U'):
        self.mem['atom_kind']=1;return 2
      if x[0]==ord('S'):
        self.mem['atom_kind']=1;return 0
      return 0
    def prefix(_):
      self.prefix_calls+=1
      v=self.av('apply_byte_prefix',0,2);p=self.av('apply_byte_prefix',1)
      return (v&255) if p==1 else ((v>>8)&255)
    self.calls={'parse_atom':atom,'apply_byte_prefix':prefix}
    got,mem,inv=super().run(100000)
    return got,mem,self.pcalls,self.prefix_calls,self.parse_hash
rng=random.Random(2026)
for i in range(3500):
    n=rng.randrange(21)
    corpus=[b'',b'42',b'1+2',b'1-2',b'<42',b'>42',b'1+U',b'S+1',b'S+S',b'?x',b'1++2',b'1+2+3',b'U-1',b'U+1',b'U+S',b'S-1',b'2+S',b'2-S',b'123-45',b'<S+1',b'>?x',b'++',b'--',b'1-',b'<']
    arg=corpus[i%len(corpus)] if i<250 else bytes(rng.choice(b'01234US?+-<>abcdefghijkl') for _ in range(n))
    env={'text':0x3000,'length':len(arg),'VALUE_BAD':1,'VALUE_OK':0,'VALUE_UNRESOLVED':2,'VALUE_PREFIX_LOW':1,'VALUE_PREFIX_HIGH':2,'VALUE_PREFIX_NONE':0,'atom_used':0,'atom_value':42,'atom_symbol':14,'atom_kind':0,'captured_symbol':-7,'captured_addend':42,'captured_prefix':0,'value_result':88}
    for k,v in env.items():
      try:
        if k in ('atom_value','atom_symbol','captured_symbol','captured_addend','value_result'):ctypes.c_uint.in_dll(lib,k).value=v&65535 # host int/unsigned 32bit
        else:ctypes.c_uint8.in_dll(lib,k).value=v&255
      except ValueError:pass
    for k in ('parse_calls','prefix_calls','parse_hash'):ctypes.c_int.in_dll(lib,k).value=0
    native=lib.parse_value(ctypes.c_char_p(arg+b'\0'),len(arg))
    oracle=(native,ctypes.c_uint.in_dll(lib,'captured_addend').value&65535,ctypes.c_int.in_dll(lib,'captured_symbol').value&65535,ctypes.c_ubyte.in_dll(lib,'captured_prefix').value,ctypes.c_uint.in_dll(lib,'value_result').value&65535,ctypes.c_int.in_dll(lib,'parse_calls').value,ctypes.c_int.in_dll(lib,'prefix_calls').value,ctypes.c_int.in_dll(lib,'parse_hash').value)
    cpu=TestCPU(src,arg,env);got,m,pa,pf,ph=cpu.run_test()
    obs=(got&255,m.get('captured_addend',0)+(m.get('captured_addend+1',0)<<8),m.get('captured_symbol',0)+(m.get('captured_symbol+1',0)<<8),m.get('captured_prefix',0),m.get('value_result',0)+(m.get('value_result+1',0)<<8),pa,pf,ph)
    if obs!=oracle:
        print('FAIL',i,arg, 'got',obs,'want',oracle,'steps',cpu.steps,flush=True)
        print('trace',cpu.trace[-30:]);break
else:print('PASS parse_value 3500 differential cases with observable globals + call histories')
