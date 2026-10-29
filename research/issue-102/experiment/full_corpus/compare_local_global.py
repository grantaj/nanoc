from pathlib import Path
from scratch_allocator import allocate
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend,LocalArgumentBackend
from execute6502 import relax
from collections import Counter
import csv
rows=[]
for fn in ('assemble_instruction','parse_value','process_source_line','parse_atom'):
 arr={'source_line':('u8',256)} if fn=='process_source_line' else {'symbol_kind':('u8',896),'symbol_payload':('s16',896)} if fn=='parse_atom' else {}
 for name,Cls in [('block_local',LocalArgumentBackend),('cross_block',ArgumentPlacementBackend)]:
  t=TapeBuilder(Path(fn+'.c').read_text()).build();b=Cls(t,arr);raw=b.run();original,raw_bytes,_=relax(raw);packed,metrics=allocate(t,b,raw)
  Path(f'{fn}.{name}.packed.asm').write_text(packed)
  # The allocator's zero-page result is CONDITIONAL on reserving actual ZP.
  row={'function':fn,'planner':name,'no_zero_page_bytes':raw_bytes,'hypothetical_zp_bytes':metrics['instruction_bytes'],'temporary_values':metrics['temporary_values'],'scratch_bytes':metrics['packed_bytes']}
  rows.append(row);print(row,flush=True)
with open('compare_planners.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
