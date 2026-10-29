"""Same tape, generic native 6502 indexed-address mode selection.
For an 8-bit byte index use absolute,Y or (zero-page),Y; do not perform
16-bit effective-address addition, which those modes implement in hardware.
"""
from backend3 import ConsumerBackend
from tape_frontend import TapeBuilder
from pathlib import Path
from execute6502 import relax
from subset6502 import parse_lines

class IndexedBackend(ConsumerBackend):
 def op(self,o):
    if o.code=='read':
       base,index=o.args
       b=self.defs[base]
       arr=b.args[0] if b.code=='load' and b.args[0] in self.arrays else None
       kind=(self.arrays[arr][0] if arr else 'u8')
       ix=self.defs[index]
       fast_index=(self.t.values[index] in ('u8','bool') or
                  ix.code=='const' and 0<=ix.args[0]<=255)
       if fast_index and kind=='u8':
          self.emit('ldy',self.val(index))
          if arr:
             self.emit('lda',arr+',y')
          else:
             self.emit('lda',self.val(base))
             self.emit('sta','__ap')
             self.emit('lda',self.val(base,True))
             self.emit('sta','__ap+1')
             self.emit('lda','(__ap),y')
          self.emit('sta','__v%d'%o.result)
          return
    return super().op(o)

if __name__=='__main__':
 t=TapeBuilder(Path(__file__).with_name('parse_atom.c').read_text()).build()
 b=IndexedBackend(t,{'symbol_kind':('u8',896),'symbol_payload':('s16',896)})
 s=b.run();s,sz,relaxations=relax(s)
 Path(__file__).with_name('parse_atom_indexed.asm').write_text(s)
 print('indexed addressing:',sz,'B',len(parse_lines(s.splitlines())[0]),'instructions',relaxations,'long branches')
