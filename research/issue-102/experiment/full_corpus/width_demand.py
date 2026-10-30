"""Research-only operation-level backward low/word demand for Nano C values.

The consumer defines which bits are *observable*. This is independent of any
source function name; once a word is consumed solely by a char destination,
we can discard its high-byte computation (modulo-256 arithmetic).
Full-width compares, indexes, pointer arithmetic and calls retain full width.
"""
from collections import defaultdict
from byte_demand import ByteDemandBackend

class WidthDemandBackend(ByteDemandBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.width_needs=defaultdict(int)
        self.narrowed=[]
        super().__init__(t,arrays,**kwargs)
        self.width_needs=defaultdict(int)
        self.compute_width_needs()
        self.narrowed=[]

    def compute_width_needs(self):
        work=[]
        def need(v,w):
            if not isinstance(v,int) or v not in self.defs:return
            w=min(w,2)
            if self.width_needs[v]<w:
                self.width_needs[v]=w
                work.append(v)
        for b in self.t.blocks:
            if b.name not in self.reach:continue
            for o in b.ops:
                c,a=o.code,o.args
                if c=='return':need(a[0],self.width(self.t.rtype))
                elif c=='store':need(a[1],self.width(self.t.types[a[0]]))
                elif c=='store_index':
                    base,idx,v=a
                    need(base,2);need(idx,self.width(self.t.values[idx]));need(v,2) # cautious: element can be word
                elif c=='call':
                    for v in a[1:]:need(v,self.width(self.t.values[v]))
                elif c=='branch':need(a[0],1)
        while work:
            v=work.pop();o=self.defs[v];c,a=o.code,o.args;w=self.width_needs[v]
            if c in ('const','string','load'):continue
            if c=='identity':need(a[0],w)
            elif c=='low8':need(a[0],1)
            elif c=='high8':need(a[0],2)
            elif c in ('+','-','*','<<','&','|','^'):
                # If only the bottom 8 bits are observed, the upper bits of
                # both operands cannot affect the result modulo 256.
                for x in a:need(x,w if x==a[0] else min(w,self.width(self.t.values[x])))
            elif c=='neg':need(a[0],w)
            elif c=='>>':
                need(a[0],2);need(a[1],2) # high bits can shift into low
            elif c in ('==','!=','<','<=','>','>='):
                for x in a:need(x,self.width(self.t.values[x]))
            elif c=='not':need(a[0],self.width(self.t.values[a[0]]))
            elif c=='read':
                need(a[0],2);need(a[1],self.width(self.t.values[a[1]]))
            elif c=='call':
                for x in a[1:]:need(x,self.width(self.t.values[x]))
            else:raise AssertionError('unhandled value-producing operation '+c)

    def arith(self,o):
        if self.width(o.type)==2 and self.width_needs[o.result]==1:
            a,b=o.args;c=o.code;dest='__v%d'%o.result
            if c in ('+','-','&','|','^'):
                self.emit('lda',self.val(a))
                if c in ('+','-'):self.emit('clc' if c=='+' else 'sec')
                self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[c],self.val(b))
                self.emit('sta',dest)
                self.narrowed.append((o.result,c))
                return
            if c=='<<' and self.defs[b].code=='const':
                n=self.defs[b].args[0]
                if n>=0:
                    self.emit('lda',self.val(a) if n<8 else '#$00')
                    self.emit('sta',dest)
                    for _ in range(min(n,7)):self.emit('asl',dest)
                    self.narrowed.append((o.result,c));return
            if c=='*' and self.defs[b].code=='const':
                n=self.defs[b].args[0]&65535
                if n<256:
                    self.emit('lda','#$00');self.emit('sta',dest)
                    self.emit('lda',self.val(a));self.emit('sta','__mw')
                    for bit in range(8):
                        if n&(1<<bit):
                            self.emit('clc');self.emit('lda',dest);self.emit('adc','__mw');self.emit('sta',dest)
                        if bit<7 and n>>(bit+1):self.emit('asl','__mw')
                    self.narrowed.append((o.result,c));return
        return super().arith(o)

    def op(self,o):
        if o.code=='neg' and self.width_needs[o.result]==1 and self.width(o.type)==2:
            self.emit('sec');self.emit('lda','#$00');self.emit('sbc',self.val(o.args[0]));self.emit('sta','__v%d'%o.result)
            self.narrowed.append((o.result,'neg'));return
        return super().op(o)
