"""Independent narrow 6502 executor for the emitted opcodes; not VICE.
Compares the generated machine programs to the *unchanged* C routines.
"""
import ctypes, pathlib, subprocess, random, re
ROOT=pathlib.Path(__file__).parent
DRIVER=ROOT/'test_driver'
subprocess.run(['cc','-std=c99','-funsigned-char','-O0',str(ROOT/'test_driver.c'),'-o',str(DRIVER)],check=True)
for test in ('same_bytes','find_global'):
    (ROOT/(test+'.asm')).write_bytes(subprocess.check_output([str(DRIVER),test]))
subprocess.run([str(DRIVER),'reject'],check=True,stdout=subprocess.DEVNULL)
SRC=ROOT/'original_oracles.c'
SO=ROOT/'original_oracles.so'
subprocess.run(['cc','-std=c99','-funsigned-char','-shared','-fPIC','-O0',str(SRC),'-o',str(SO)],check=True)
lib=ctypes.CDLL(str(SO))

class Machine:
    def __init__(self,listing):
        self.program=[];self.labels={};self.pc=0
        self.a=0;self.x=0;self.y=0;self.c=0;self.z=0;self.n=0
        self.m=bytearray(65536)
        self.addr={'__v1':0x20,'__v2':0x21,'__v3':0x22,'__v4':0x23,'__v5':0x24,
                   '__twlo':0x25,'__twhi':0x26,'__tptr00':0x27,'__tptr01':0x29,
                   'global_name_len':0x5E20,'global_name':0x6010,'token_text':0x8018}
        for line in listing.splitlines():
            line=line.strip().lower()
            if not line: continue
            if line.endswith(':'):
                self.labels[line[:-1]]=len(self.program)
            else:
                op,*arg=line.split(None,1)
                self.program.append((op,arg[0] if arg else ''))
    def address(self,s):
        s=s.strip()
        if s.endswith('+1'):return self.addr[s[:-2]]+1
        return self.addr[s]
    def rd(self,s):
        if s.startswith('#$'):return int(s[2:],16)
        if s.startswith('#<'):return self.address(s[2:])&255
        if s.startswith('#>'):return self.address(s[2:])>>8
        if s.startswith('('):
            q,reg=s[1:].split('),')
            assert reg=='y',s
            address=self.m[self.address(q)] | self.m[self.address(q)+1]<<8
            return self.m[(address+self.y)&0xffff]
        if s.endswith(',y'):return self.m[(self.address(s[:-2])+self.y)&65535]
        if s.endswith(',x'):return self.m[(self.address(s[:-2])+self.x)&65535]
        return self.m[self.address(s)]
    def wr(self,s,n):
        self.m[self.address(s)]=n&255
    def nz(self,n):
        self.z=int((n&255)==0); self.n=int(bool(n&128))
    def run(self,maxsteps=100000):
        n=0
        while n<maxsteps:
            n+=1
            op,arg=self.program[self.pc];self.pc+=1
            if op in ('lda','ldx','ldy'):
                v=self.rd(arg); setattr(self,op[-1],v);self.nz(v)
            elif op in ('sta','stx','sty'):self.wr(arg,getattr(self,op[-1]))
            elif op=='cmp' or op=='cpx' or op=='cpy':
                v=self.rd(arg);a={'cmp':self.a,'cpx':self.x,'cpy':self.y}[op];z=a-v
                self.c=int(z>=0);self.nz(z)
            elif op=='clc':self.c=0
            elif op=='sec':self.c=1
            elif op in ('asl','rol'):
                a=self.rd(arg);cc=self.c
                self.c=(a>>7)&1
                v=((a<<1)|(cc if op=='rol' else 0))&255
                self.wr(arg,v);self.nz(v)
            elif op=='adc':
                v=self.a+self.rd(arg)+self.c
                self.c=int(v>255);self.a=v&255;self.nz(v)
            elif op=='inx':self.x=(self.x+1)&255;self.nz(self.x)
            elif op=='iny':self.y=(self.y+1)&255;self.nz(self.y)
            elif op=='txa':self.a=self.x;self.nz(self.a)
            elif op=='tya':self.a=self.y;self.nz(self.a)
            elif op=='tax':self.x=self.a;self.nz(self.x)
            elif op=='tay':self.y=self.a;self.nz(self.y)
            elif op=='jmp':self.pc=self.labels[arg]
            elif op in ('bne','beq','bcc','bcs'):
                valid={'bne':not self.z,'beq':self.z,'bcc':not self.c,'bcs':self.c}[op]
                if valid:self.pc=self.labels[arg]
            elif op=='rts':return self.a,n
            else:raise AssertionError((op,arg))
        raise RuntimeError('instruction budget exceeded')

# Physical byte count, including 6502 zero-page addressing for known homes.
def image_size(lines):
    size=0
    m=Machine(lines)
    for op,arg in m.program:
        if not arg:size+=1
        elif op[0]=='b' and op!='bit':size+=2
        elif arg.startswith('#'):size+=2
        elif arg.startswith('('):size+=2
        elif arg.endswith(',x') or arg.endswith(',y'):
            size+=3 if not arg.startswith('(') else 2
        elif op=='jmp':size+=3
        elif m.address(arg)<256:size+=2
        else:size+=3
    return size

rand=random.Random(7816)
lines1=(ROOT/'same_bytes.asm').read_text();lines2=(ROOT/'find_global.asm').read_text()
lib.same_bytes.argtypes=[ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ubyte,ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ubyte]
lib.same_bytes.restype=ctypes.c_ubyte
for q in range(4000):
    length=rand.randrange(0,256);other=length if q%7 else rand.randrange(0,256)
    a=bytearray(rand.randrange(256) for _ in range(256));b=bytearray(a)
    if q%3==0 and length:b[rand.randrange(length)]=rand.randrange(256)
    ac=(ctypes.c_ubyte*256).from_buffer_copy(a)
    bc=(ctypes.c_ubyte*256).from_buffer_copy(b)
    expected=lib.same_bytes(ac,length,bc,other)
    machine=Machine(lines1)
    # Page crossing is intentional: pointer0 at $40F0, pointer1 at $51E8.
    for ix,v in enumerate(a):machine.m[(0x40f0+ix)&65535]=v
    for ix,v in enumerate(b):machine.m[(0x51e8+ix)&65535]=v
    machine.m[0x27]=0xf0;machine.m[0x28]=0x40
    machine.m[0x29]=0xe8;machine.m[0x2a]=0x51
    machine.m[0x22]=length;machine.m[0x23]=other
    actual,_=machine.run()
    assert actual==expected,('same_bytes',q,actual,expected)

lib.find_global.argtypes=[];lib.find_global.restype=ctypes.c_ubyte
gname=(ctypes.c_ubyte*5632).in_dll(lib,'global_name')
glen=(ctypes.c_ubyte*176).in_dll(lib,'global_name_len')
token=(ctypes.c_ubyte*192).in_dll(lib,'token_text')
tokenlen=ctypes.c_ubyte.in_dll(lib,'token_length')
gcount=ctypes.c_ubyte.in_dll(lib,'global_count')
for q in range(2500):
    count=rand.randrange(0,177);name_len=rand.randrange(0,32)
    # Favor both hit and miss, including long tables and 32-byte records.
    for j in range(count):
        glen[j]=rand.randrange(32)
        for k in range(32):gname[j*32+k]=rand.randrange(256)
    for k in range(name_len):token[k]=rand.randrange(256)
    if count and q%2==0:
        j=rand.randrange(count);glen[j]=name_len
        for k in range(name_len):gname[j*32+k]=token[k]
    tokenlen.value=name_len;gcount.value=count
    expected=lib.find_global()
    machine=Machine(lines2)
    machine.m[machine.addr['global_name_len']:machine.addr['global_name_len']+176]=bytes(glen)
    machine.m[machine.addr['global_name']:machine.addr['global_name']+5632]=bytes(gname)
    machine.m[machine.addr['token_text']:machine.addr['token_text']+192]=bytes(token)
    machine.m[0x23]=name_len;machine.m[0x24]=count
    actual,_=machine.run()
    assert actual==expected,('find_global',q,count,actual,expected)

print(f'same_bytes: 4000/4000, {image_size(lines1)} 6502 bytes')
print(f'find_global: 2500/2500, {image_size(lines2)} 6502 bytes')
print('Total 6500 host-C/machine comparisons passed; three rejection guards passed')
