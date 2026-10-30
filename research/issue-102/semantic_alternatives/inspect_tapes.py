"""Inspect real recovered #102 typed tapes; no source-code optimisation rules."""
from pathlib import Path
from collections import Counter
import sys,json
BASE=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parents[1]/'nanoc_machine_value_home_planner'
sys.path.insert(0,str(BASE/'full_corpus'))
from tape_frontend import TapeBuilder
functions=('assemble_instruction','find_symbol','stage_byte','stage_resolved_instruction')
summary=[]
for name in functions:
 tape=TapeBuilder((BASE/'full_corpus'/'whole_corpus'/(name+'.c')).read_text()).build()
 ops=[(b.name,o) for b in tape.blocks for o in b.ops]
 defs={o.result:o for _,o in ops if o.result>=0}
 indexed=[]
 for block,o in ops:
  if o.code not in ('read','store_index'):continue
  base,ind=o.args[:2]
  bo,io=defs[base],defs[ind]
  indexed.append({'block':block,'op':o.code,'array_or_pointer':bo.args[0] if bo.code=='load' else bo.code,'index_type':tape.values[ind], 'index_producer':io.code, 'producer_args':repr(io.args)})
 summary.append({'function':name,'blocks':len(tape.blocks),'ops':len(ops),'calls':sum(o.code=='call' for _,o in ops),'indexed':indexed,'scalar_stores':dict(Counter(o.args[0] for _,o in ops if o.code=='store'))})
print(json.dumps(summary,indent=2))
