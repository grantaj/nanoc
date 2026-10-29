"""Research-only function-wide Y register physical-home alternative.

Selects a byte local/parameter (never a global) whose every memory access can
be replaced with a 6502 Y-register operation. Rejects functions that otherwise
use Y; spills the byte across calls in its original static slot; preserves
flags around restores. Selection is by *total measured instruction cost*, not
function name or source-text pattern. This is an adversarial experiment in
register residency over all CFG blocks, not a local operand cache.
"""
from pathlib import Path
import re,json
from collections import Counter
from execute6502 import parse_lines
P=Path(__file__).resolve().parent
lines=(P/'functions.asm').read_text().splitlines()
starts=[]
for i,line in enumerate(lines):
 if re.fullmatch(r'[A-Za-z][\w]*:',line):starts.append((i,line[:-1]))
starts.append((len(lines),'__END__'))
out=[];results=[];candidates=[]
YOPS={'ldy','sty','iny','dey','tay','tya','cpy'}
# conservative physical opcode dependency check
for (start,name),(end,_) in zip(starts,starts[1:]):
 code=lines[start:end]; ops=[]
 for i,line in enumerate(code):
  m=re.match(r'\s*([a-z]{3})(?:\s+(.*))?$',line)
  if m:ops.append((i,m[1],(m[2] or '').strip()))
 forbidden=any(op in YOPS or re.search(r'\),\s*y\b|,\s*y\b',arg) for _,op,arg in ops)
 uses=Counter();other=Counter()
 for idx,op,arg in ops:
  m=re.fullmatch(r'(__L_'+re.escape(name)+r'_\w+)(\+1)?',arg)
  if m:
   var=m[1]
   if m[2] or op not in ('lda','sta','inc','dec'):other[var]+=1
   else:uses[var]+=1
 best=None
 # A location assigned to Y must also have a definition before any read
 # on each path. Variables whose only definition is an entry parameter must
 # receive an entry LDY load; the existing ABI A-arg prologue also qualifies.
 if not forbidden:
  for var,n in uses.items():
   if other[var] or n<2:continue
   # Count size difference, including caller spill and callee restore.
   # No local whose address may be observed: source frontend lacks unary &.
   # Word locals and pointer halves are rejected (size comes from source).
   sym=json.loads((P/'local_storage.json').read_text())
   if sym.get(var)!=1:continue
   changed=[];saving=0
   for i,line in enumerate(code):
    m=re.match(r'^(\s*)(lda|sta|inc|dec)\s+'+re.escape(var)+r'\s*$',line)
    if m:
     subst={'lda':'tya','sta':'tay','inc':'iny','dec':'dey'}[m[2]]
     changed.append(m[1]+subst)
     saving+=2 if m[2] in ('lda','sta') else 2
    else:
     mm=re.match(r'^(\s*)jsr\s+\w+\s*$',line)
     if mm:
      # Spill BEFORE call; restore after. Flag-safe restoration: LDY changes NZ;
      # PHP/PLP preserve actual return flags and carry.
      changed.extend(['    sty '+var,line,'    php','    ldy '+var,'    plp'])
      saving-=3+1+3+1
     else:changed.append(line)
   # initial register home for parameter at entry, unless the entry instruction
   # already overwrites via TAY; register remains live over all CFG boundaries.
   entry=next((i for i,x in enumerate(changed) if x.endswith('_entry:')),None)
   if entry is None:continue
   # all param slot variables have a stable value from the caller; local may
   # start undefined, but conservative initial LDY is always defined on machine.
   changed.insert(entry+1,'    ldy '+var);saving-=3
   # If the function writes scalar via alias? local addresses never escape.
   candidates.append(dict(name=name,var=var,original_uses=n,saving=saving,jsr=sum(x[1]=='jsr' for x in ops)))
   if best is None or saving>best[0]:best=(saving,var,changed)
 if best and best[0]>0:
  out.extend(best[2]);results.append(dict(name=name,variable=best[1],estimated_saving=best[0]))
 else:out.extend(code)
(P/'functions.asm').write_text('\n'.join(out)+'\n')
(P/'y_home_stats.json').write_text(json.dumps(dict(selected=results,candidates=candidates),indent=2))
print('Y-region-home',len(results),'functions; est savings',sum(x['estimated_saving'] for x in results))
for x in results:print(x)
