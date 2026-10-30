"""Execute operation tape independently of host-C oracle.
This is validation of typed tape *semantics*, not validation of 6502 code.
"""
from tape_frontend import TapeBuilder

class VM:
    def __init__(self,tape,mem,arrays=None,call_impl=None):
        self.t=tape;self.mem=dict(mem);self.arrays=arrays or {};self.call_impl=call_impl or {}
        self.ids={};self.steps=0;self.call_counts={}
    def normalize(self,n,k):
        if k in ('u8','bool'):return n&255
        if k in ('u16','s16'):return n&65535
        return n
    def signed(self,n,k):
        if k=='s16':return ((n&65535)^32768)-32768
        if k in ('u8','bool'):return n&255
        return n&65535
    def val(self,i):return self.ids[i]
    def run(self):
        blocks={b.name:b for b in self.t.blocks};bname='entry'
        while True:
            for op in blocks[bname].ops:
                self.steps+=1
                if self.steps>40000:raise TimeoutError('tape infinite loop')
                c,args,k,d=op.code,op.args,op.type,op.result
                if c=='const':v=args[0]
                elif c=='load':
                    v=args[0] if args[0] in self.arrays else self.mem.get(args[0],0)
                elif c=='read':
                    base,index=self.val(args[0]),self.val(args[1])
                    a=self.arrays[base];v=a[index]
                elif c=='call':
                    vals=[self.val(x) for x in args[1:]]
                    self.call_counts[args[0]]=self.call_counts.get(args[0],0)+1
                    v=self.call_impl[args[0]](*vals)
                elif c=='neg':v=-self.val(args[0])
                elif c=='not':v=int(self.val(args[0])==0)
                elif c in ('+','-','*','<<','>>','|','&','^'):
                    a,z=(self.val(x) for x in args)
                    v={'+':lambda:a+z,'-':lambda:a-z,'*':lambda:a*z,'<<':lambda:a<<z,'>>':lambda:a>>z,
                       '|':lambda:a|z,'&':lambda:a&z,'^':lambda:a^z}[c]()
                elif c in ('==','!=','<','<=','>','>='):
                    a,z=(self.val(x) for x in args)
                    lhs,rhs=(self.t.values[x] for x in args)
                    if lhs=='u16' or rhs=='u16':a=a&65535;z=z&65535
                    else:a=self.signed(a,lhs);z=self.signed(z,rhs)
                    v=int({'==':lambda:a==z,'!=':lambda:a!=z,'<':lambda:a<z,'<=':lambda:a<=z,
                           '>':lambda:a>z,'>=':lambda:a>=z}[c]())
                elif c=='store':
                    name,v=args;self.mem[name]=self.normalize(self.val(v),self.t.types[name]);continue
                elif c=='branch':
                    cond,yes,no=args;bname=yes if self.val(cond) else no;break
                elif c=='jump':bname=args[0];break
                elif c=='return':return self.normalize(self.val(args[0]),self.t.rtype),self.mem,self.call_counts
                else:raise NotImplementedError(c)
                if d>=0:self.ids[d]=self.normalize(v,k)
            else:raise ValueError('unterminated '+bname)
