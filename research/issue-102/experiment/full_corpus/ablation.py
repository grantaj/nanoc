from pathlib import Path
from collections import Counter
import sys
sys.path.insert(0,str(Path(__file__).parent))
from tape_frontend import TapeBuilder
from backend4 import IndexedBackend
from loop_backend import LoopBackend
from state_backend import StateBackend
from a_backend import ABackend
from execute6502 import relax
class ArrayAddressMixin:
 def val(self,v,high=False):
  d=self.defs[v]
  if d.code=='load' and d.args[0] in self.arrays:
   return ('#>' if high else '#<')+d.args[0]
  return super().val(v,high)
class Indexed(ArrayAddressMixin,IndexedBackend):pass
class Loop(ArrayAddressMixin,LoopBackend):pass
class Memory(ArrayAddressMixin,StateBackend):pass
class Machine(ArrayAddressMixin,ABackend):pass
for fn in ('assemble_instruction','parse_value','process_source_line'):
 arr={'source_line':('u8',256)} if fn=='process_source_line' else {}
 print(fn,end=' ')
 for cls in (Indexed,Loop,Memory,Machine):
  t=TapeBuilder(Path(fn+'.c').read_text()).build()
  b=cls(t,arr)
  s,n,r=relax(b.run())
  print(cls.__name__,n,end='; ')
 print()
