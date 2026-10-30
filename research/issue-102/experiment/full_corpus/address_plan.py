"""Machine-address residency for multiple indexed accesses (research-only).

A block-local must-state: __ix holds a scaled 16-bit index and __ap holds
an effective address. Equivalent typed scalar snapshots may share these
machine locations until any actual clobber, source mutation, indirect write,
call, or CFG label. There are no function-name-dependent rules.
"""
from const_fold import FoldedBackend

class AddressPlanBackend(FoldedBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.index_state=None
        self.pointer_state=None
        self.building_address=False
        self.address_hits=0
        self.index_hits=0
        super().__init__(t,arrays,**kwargs)
        # ABackend constructs a baseline/probe emission inside __init__.
        # Metrics and residency facts below refer to the *real* pass only.
        self.address_hits=self.index_hits=0
        self.index_state=self.pointer_state=None

    def _identity(self,vid):
        op=self.defs[vid]
        if op.code=='load':
            return ('name',op.args[0])
        if op.code=='const':
            return ('const',op.args[0]&65535)
        return ('value',vid)

    def _deps(self,identity):
        return {identity[1]} if identity[0]=='name' else set()

    def emit(self,op,arg=None):
        if not getattr(self,'building_address',False):
            # A call can overwrite all caller scratch. A new write to either
            # scratch register invalidates its machine-state promise.
            if op=='jsr':
                self.index_state=None;self.pointer_state=None
            if arg in ('__ix','__ix+1') and op in ('sta','stx','sty','inc','dec','asl','lsr','rol','ror'):
                self.index_state=None
            if arg in ('__ap','__ap+1') and op in ('sta','stx','sty','inc','dec','asl','lsr','rol','ror'):
                self.pointer_state=None
        return super().emit(op,arg)

    def mark(self,label):
        # Cross-block state requires a predecessor-intersection proof; this
        # deliberately does not preserve either location across a label.
        self.index_state=None;self.pointer_state=None
        return super().mark(label)

    def op(self,o):
        if o.code=='call':
            self.index_state=None;self.pointer_state=None
            return super().op(o)
        if o.code=='store_index':
            base=self.defs[o.args[0]]
            # A named C array has disjoint storage from scalar index/
            # pointer variables. An arbitrary pointer store has no such
            # guarantee and invalidates both residency facts.
            known=(base.code=='load' and base.args[0] in self.arrays)
            try:return super().op(o)
            finally:
                if not known:
                    self.index_state=None;self.pointer_state=None
        if o.code=='store':
            dst=o.args[0]
            for attr in ('index_state','pointer_state'):
                k=getattr(self,attr)
                if k is not None and dst in (self._deps(k[0]) if attr=='index_state' else k[2]):setattr(self,attr,None)
        return super().op(o)

    def array_ptr(self,base,index):
        obj=self.defs[base]
        arr=obj.args[0] if obj.code=='load' and obj.args[0] in self.arrays else None
        elem=self.arrays[arr][0] if arr else 'u8'
        stride=2 if elem in ('u16','s16') else 1
        idxkey=(self._identity(index),stride)
        basekey=('array',arr) if arr else self._identity(base)
        deps=self._deps(idxkey[0]) | (set() if arr else self._deps(basekey))
        addrkey=(basekey,idxkey,frozenset(deps))
        if self.pointer_state==addrkey:
            self.address_hits+=1
            return elem
        cached=self.index_state==idxkey
        self.building_address=True
        try:
            if arr:
                self.emit('lda','#<'+arr);self.emit('sta','__ap')
                self.emit('lda','#>'+arr);self.emit('sta','__ap+1')
            else:
                self.emit('lda',self.val(base));self.emit('sta','__ap')
                self.emit('lda',self.val(base,True));self.emit('sta','__ap+1')
            if not cached:
                if stride==2:
                    self.emit('lda',self.val(index));self.emit('asl');self.emit('sta','__ix')
                    self.emit('lda',self.val(index,True));self.emit('rol');self.emit('sta','__ix+1')
                else:
                    self.emit('lda',self.val(index));self.emit('sta','__ix')
                    self.emit('lda',self.val(index,True));self.emit('sta','__ix+1')
            self.emit('clc');self.emit('lda','__ap');self.emit('adc','__ix');self.emit('sta','__ap')
            self.emit('lda','__ap+1');self.emit('adc','__ix+1');self.emit('sta','__ap+1')
        finally:
            self.building_address=False
        if cached:self.index_hits+=1
        self.index_state=idxkey
        self.pointer_state=addrkey
        return elem
