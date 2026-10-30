from pathlib import Path
import sys, traceback
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,'/mnt/data/nanoc_loop_state_trial')
from tape_frontend import TapeBuilder
from a_backend import ABackend
from execute6502 import relax
from collections import Counter
for fn in ('parse_value','assemble_instruction','process_source_line'):
    print('-----',fn,flush=True)
    t=TapeBuilder((ROOT/(fn+'.c')).read_text()).build()
    try:
        b=ABackend(t,{'source_line':('u8',256)} if fn=='process_source_line' else {})
        s,sz,f=relax(b.run())
        (ROOT/(fn+'.asm')).write_text(s)
        print('SUCCESS',sz,'bytes,',f,'long branches,',b.avoided_lda,'A loads saved; loops:',len(b.plans),'rejected',b.rejected[:8],flush=True)
    except Exception as e:
        print('FAIL',type(e).__name__,str(e),flush=True)
        traceback.print_exc(limit=4)
