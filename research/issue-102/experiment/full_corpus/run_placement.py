from pathlib import Path
from collections import Counter
from tape_frontend import TapeBuilder
from placement_backend import PlacementBackend,LocalPlacementBackend
from large_backend import LargeBackend
from execute6502 import relax
from subset6502 import parse_lines
import csv
files=('assemble_instruction','parse_value','process_source_line')
rows=[]
for fn in files:
    t=TapeBuilder(Path(fn+'.c').read_text()).build()
    arr={'source_line':('u8',256)} if fn=='process_source_line' else {}
    for label,Cls in [('full_state',LargeBackend),('full_state+placement',PlacementBackend),('local+placement',LocalPlacementBackend)]:
        # Avoid reusing the tape: inherited CFG canonicalisation mutates blocks.
        fresh=TapeBuilder(Path(fn+'.c').read_text()).build()
        b=Cls(fresh,arr)
        asm,n,nbranch=relax(b.run())
        out=f'{fn}.{label}.asm'
        Path(out).write_text(asm)
        row={'function':fn,'variant':label,'bytes':n,'instructions':len(parse_lines(asm.splitlines())[0]),'long_branches':nbranch,'temp_slots':len(set(x for x in __import__('re').findall(r'__v\d+',asm))), 'sinks':dict(getattr(b,'forwarded',{}))}
        rows.append(row)
        print(row,flush=True)
    # Existing differential scripts consume the baseline names. Use the
    # new *generated* code for the same actual independent oracle tests.
    Path(fn+'.asm').write_text(Path(f'{fn}.full_state+placement.asm').read_text())
with open('placement_metrics.csv','w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=['function','variant','bytes','instructions','long_branches','temp_slots','sinks']);wr.writeheader();wr.writerows(rows)
