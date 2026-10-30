"""Generic source-array address lowering missing from research backend.
An array expression in a value context (call argument, pointer arithmetic)
decays to its address. It is not a load from a scalar slot.
"""
from pathlib import Path
from a_backend import ABackend
from tape_frontend import TapeBuilder
from execute6502 import relax

class LargeBackend(ABackend):
 def val(self,v,high=False):
    d=self.defs[v]
    if d.code=='load' and d.args[0] in self.arrays:
       return ('#>' if high else '#<')+d.args[0]
    return super().val(v,high)

if __name__=='__main__':
 for fn in ('parse_value','assemble_instruction','process_source_line'):
    t=TapeBuilder(Path(fn+'.c').read_text()).build()
    b=LargeBackend(t,{'source_line':('u8',256)} if fn=='process_source_line' else {})
    s,n,branch=relax(b.run())
    Path(fn+'.asm').write_text(s)
    print(fn,n,'bytes',branch,'long branches')
