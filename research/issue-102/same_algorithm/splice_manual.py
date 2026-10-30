"""Replace two original C compiler bodies by 6502 implementations of the SAME C algorithms.

No change to symbol/fixup layout, source C, runtime or call ABI. This is a
controlled compiler-quality calibration, not a proposed production transformation.
"""
from pathlib import Path
P=Path(__file__).resolve().parent
R=P.parent/'experiment'
p=R/'functions.asm'
s=p.read_text()
for name,following,body in (
 ('find_symbol','allocate_symbol','manual_find_symbol.asm'),
 ('stage_byte','stage_plain_word_reference','manual_stage_byte.asm'),
):
 begin=s.index(name+':\n')
 end=s.index(following+':\n',begin)
 manual='\n'.join(row for row in (P/body).read_text().splitlines()
   if row.strip() and not row.lstrip().startswith(';'))+'\n'
 s=s[:begin]+manual+'\n'+s[end:]
 print('REPLACED',name,'original lines',s[begin:end].count('\n'),
       'manual lines',manual.count('\n'))
p.write_text(s)
