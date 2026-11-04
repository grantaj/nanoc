"""Instruction-level 6502 interpreter shared by nanoc2 backend tests."""

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
        # Real 6502 STA also supports indexed absolute and (zp),Y.
        if s.startswith('('):
            q,reg=s[1:].split('),')
            assert reg=='y',s
            zp=self.address(q)
            base=self.m[zp] | self.m[zp+1]<<8
            address=(base+self.y)&65535
        elif s.endswith(',y'):
            address=(self.address(s[:-2])+self.y)&65535
        elif s.endswith(',x'):
            address=(self.address(s[:-2])+self.x)&65535
        else:
            address=self.address(s)
        self.m[address]=n&255
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
