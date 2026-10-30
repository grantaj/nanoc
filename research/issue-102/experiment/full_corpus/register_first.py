"""Alternative machine-first A residency on the same typed operation tape.

The emitted machine state is (the set of stable memory/immediate locations
holding A, NZ=A?).  Crucially, eliminating LDA is a *flag-sensitive machine
choice*, not an assumption that equal expression IDs imply equal flags.
Locations are discarded at every assembler label and unknown alias/call.
This is intentionally conservative and does not need a register allocator.
"""
from direct_address import DirectAddressBackend

class RegisterFirstBackend(DirectAddressBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.a_locations=set();self.nz_matches_a=False;self.avoided_a_loads=0
        super().__init__(t,arrays,**kwargs)
        self.a_locations=set();self.nz_matches_a=False;self.avoided_a_loads=0

    def mark(self,label):
        self.a_locations.clear();self.nz_matches_a=False
        return super().mark(label)

    @staticmethod
    def stable(s):
        return bool(s) and not (s.startswith('(') or ',y' in s or ',x' in s)

    def emit(self,op,arg=None):
        if not getattr(self,'_probe',True) and op=='lda' and self.stable(arg) and self.nz_matches_a and arg in self.a_locations:
            self.avoided_a_loads+=1
            return
        before=len(self.lines)
        ret=super().emit(op,arg)
        if getattr(self,'_probe',True) or len(self.lines)==before:
            return ret
        # Model the physical processor, not a C syntax tree.
        if op=='lda':
            self.a_locations={arg} if self.stable(arg) else set()
            self.nz_matches_a=True
        elif op=='sta':
            if self.stable(arg):
                self.a_locations.add(arg)
            else:
                self.a_locations.clear() # potential alias to every scalar
        elif op in ('stx','sty','inc','dec'):
            # X/Y or a memory increment can invalidate an A-backed home.
            self.a_locations.clear()
            if op in ('inc','dec'):self.nz_matches_a=False
        elif op in ('adc','sbc','and','ora','eor','pla','txa','tya') or (op in ('asl','lsr','rol','ror') and not arg):
            self.a_locations.clear();self.nz_matches_a=True
        elif op in ('asl','lsr','rol','ror'):
            self.a_locations.clear();self.nz_matches_a=False
        elif op in ('tax','tay'):
            self.nz_matches_a=True
        elif op in ('ldx','ldy','inx','iny','dex','dey','cpy','cpx','cmp','bit'):
            self.nz_matches_a=False
        elif op=='jsr':
            self.a_locations.clear();self.nz_matches_a=False
        elif op in ('clc','sec','jmp','rts','beq','bne','bcc','bcs','bmi','bpl','bvc','bvs','cld','sei','cli','nop'):
            pass
        else:
            self.a_locations.clear();self.nz_matches_a=False
        return ret
