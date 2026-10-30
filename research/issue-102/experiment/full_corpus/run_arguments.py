from pathlib import Path
from collections import Counter
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend,LocalArgumentBackend,PlacementBackend,LocalPlacementBackend
from execute6502 import relax
from subset6502 import parse_lines
import csv,re
files=('assemble_instruction','parse_value','process_source_line')
rows=[]
for fn in files:
    arr={'source_line':('u8',256)} if fn=='process_source_line' else {}
    for label,Cls in [('full+dest',PlacementBackend),('full+dest+arg',ArgumentPlacementBackend),('local+dest+arg',LocalArgumentBackend)]:
        t=TapeBuilder(Path(fn+'.c').read_text()).build()
        b=Cls(t,arr)
        asm,n,branches=relax(b.run())
        Path(f'{fn}.{label}.asm').write_text(asm)
        row={'function':fn,'variant':label,'bytes':n,'instructions':len(parse_lines(asm.splitlines())[0]),'long_branches':branches,'temp_slots':len(set(re.findall(r'__v\d+',asm))), 'call_results':sum(b.forwarded.values()),'arg_producers':dict(getattr(b,'arg_counts',{}))}
        print(row,flush=True);rows.append(row)
    Path(fn+'.asm').write_text(Path(f'{fn}.full+dest+arg.asm').read_text())
with open('argument_metrics.csv','w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
