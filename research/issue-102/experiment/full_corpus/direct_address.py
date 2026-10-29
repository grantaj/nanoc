"""Experiment: fold a byte-array's constant address into a wide index addition.
No function dispatch or source pattern. Wide index remains full 16 bit.
Do not cache an address if scalar identity/effect proof is missing.
"""
from address_plan import AddressPlanBackend

class DirectAddressBackend(AddressPlanBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.direct_byte_address=0
        super().__init__(t,arrays,**kwargs)
        self.direct_byte_address=0

    def array_ptr(self,base,index):
        obj=self.defs[base]
        arr=obj.args[0] if obj.code=='load' and obj.args[0] in self.arrays else None
        elem=self.arrays[arr][0] if arr else 'u8'
        if not arr:
            return super().array_ptr(base,index)
        idxkey=(self._identity(index),2 if elem in ('u16','s16') else 1)
        basekey=('array',arr)
        deps=self._deps(idxkey[0])
        addrkey=(basekey,idxkey,frozenset(deps))
        if self.pointer_state==addrkey:
            self.address_hits+=1
            return elem
        self.building_address=True
        try:
            if elem in ('u16','s16'):
                self.emit('lda',self.val(index));self.emit('asl');self.emit('sta','__ix')
                self.emit('lda',self.val(index,True));self.emit('rol');self.emit('sta','__ix+1')
                self.emit('clc')
                self.emit('lda','__ix');self.emit('adc','#<'+arr);self.emit('sta','__ap')
                self.emit('lda','__ix+1');self.emit('adc','#>'+arr);self.emit('sta','__ap+1')
            else:
                self.emit('clc')
                self.emit('lda',self.val(index))
                self.emit('adc','#<'+arr)
                self.emit('sta','__ap')
                self.emit('lda',self.val(index,True))
                self.emit('adc','#>'+arr)
                self.emit('sta','__ap+1')
        finally:
            self.building_address=False
        self.pointer_state=addrkey
        self.index_state=idxkey if elem in ('u16','s16') else None
        self.direct_byte_address+=1
        return elem
