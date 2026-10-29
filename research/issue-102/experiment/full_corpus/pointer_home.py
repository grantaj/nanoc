"""Experimental 6502-native pointer home: (zp),Y for fixed byte fields.

Same typed tape; no source/function names recognised. A stable loaded C pointer
can remain in a shared two-byte ZP home while subsequent constant-offset (or
byte-indexed) accesses use Y; the home is invalidated at all paths/effects that
might change the pointer or the target ZP register.
"""
from direct_address import DirectAddressBackend

class PointerHomeBackend(DirectAddressBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.ptr_home=None;self.setting_home=False;self.ptr_hits=0;self.ptr_loads=0
        super().__init__(t,arrays,**kwargs)
        self.ptr_home=None;self.setting_home=False;self.ptr_hits=0;self.ptr_loads=0

    def mark(self,label):
        self.ptr_home=None
        return super().mark(label)

    def emit(self,op,arg=None):
        if not self.setting_home and op in ('sta','stx','sty','inc','dec','asl','lsr','rol','ror') and arg in ('__ap','__ap+1'):
            self.ptr_home=None
        if op=='jsr':self.ptr_home=None
        return super().emit(op,arg)

    def _candidate(self,o):
        if o.code not in ('read','store_index'):return None
        base,index=o.args[:2]
        src=self.defs[base]
        if src.code!='load' or src.args[0] in self.arrays or self.t.values[base]!='ptr':return None
        iv=self.defs[index]
        if not (self.t.values[index] in ('u8','bool') or iv.code=='const' and 0<=iv.args[0]<=255):return None
        if o.code=='read' and o.type!='u8':return None
        if o.code=='store_index' and self.t.values[o.args[2]] not in ('u8','bool','s16','u16'):return None
        return src.args[0],base,index

    def _ensure_home(self,key,base):
        if self.ptr_home==key:
            self.ptr_hits+=1;return
        self.setting_home=True
        try:
            self.emit('lda',self.val(base));self.emit('sta','__ap')
            self.emit('lda',self.val(base,True));self.emit('sta','__ap+1')
        finally:self.setting_home=False
        self.ptr_home=key;self.ptr_loads+=1

    def op(self,o):
        if getattr(self,'_probe',False):return super().op(o)
        cand=self._candidate(o)
        if (cand and o.result not in getattr(self,'read_alias',{})
                and o.result not in getattr(self,'sinks',{})
                and o.result not in getattr(self,'arg_targets',{})):
            key,base,index=cand
            self._ensure_home(key,base)
            self.emit('ldy',self.val(index))
            if o.code=='read':
                self.emit('lda','(__ap),y')
                if o.result not in getattr(self,'direct_reads',{}):self.emit('sta','__v%d'%o.result)
            else:
                self.emit('lda',self.val(o.args[2]));self.emit('sta','(__ap),y')
                # A possibly aliasing pointer write may alter the pointer itself.
                self.ptr_home=None
            return
        if o.code=='store':
            if self.ptr_home is not None and self.ptr_home==o.args[0]:self.ptr_home=None
        if o.code=='store_index':self.ptr_home=None
        if o.code=='call':self.ptr_home=None
        return super().op(o)
