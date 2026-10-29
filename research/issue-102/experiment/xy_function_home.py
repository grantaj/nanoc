"""Adversarial function-spanning register-home planner for both X and Y.

Candidate home assignments are byte locals whose address cannot escape. An
entire function receives one register home only if every original use of that
register is absent, so no alternative live machine register is displaced.
Calls spill and restore through existing home; PHP/PLP preserve NZCV.
Compares actual output cost for all candidate locals. Deterministic tie break.
"""
from pathlib import Path
import re,json
from collections import Counter
P=Path(__file__).resolve().parent
lines=(P/'functions.asm').read_text().splitlines()
orig={}
starts=[(i,m.group(1)) for i,s in enumerate(lines) if (m:=re.fullmatch(r'([A-Za-z][\w]*):',s))]
starts.append((len(lines),'__END__'))
out=[];results=[];candidates=[]
localsizes=json.loads((P/'local_storage.json').read_text())
for (start,name),(end,_) in zip(starts,starts[1:]):
 code=lines[start:end];ops=[]
 for i,line in enumerate(code):
  m=re.match(r'\s*([a-z]{3})(?:\s+(.*))?$',line)
  if m:ops.append((i,m[1],(m[2] or '').strip()))
 best=None
 uses=Counter();other=Counter()
 for i,op,arg in ops:
  m=re.fullmatch(r'(__L_'+re.escape(name)+r'_\w+)(\+1)?',arg)
  if m:
   var=m[1]
   if m[2] or op not in ('lda','sta','inc','dec'):other[var]+=1
   else:uses[var]+=1
 for reg in 'xy':
  if reg=='x':
   forbidden={'ldx','stx','inx','dex','tax','txa','cpx'}
  else:forbidden={'ldy','sty','iny','dey','tay','tya','cpy'}
  if any(op in forbidden or re.search(r'\),\s*'+reg+r'\b|,\s*'+reg+r'\b',arg) for _,op,arg in ops):continue
  for var,n in uses.items():
   if other[var] or localsizes.get(var)!=1 or n<2:continue
   opset={'lda':f't{reg}a','sta':f'ta{reg}','inc':f'in{reg}','dec':f'de{reg}'}
   # X: TXA, TAX, INX DEX. Y: TYA, TAY, INY, DEY
   mapping={'lda':'txa' if reg=='x' else 'tya','sta':'tax' if reg=='x' else 'tay','inc':'inx' if reg=='x' else 'iny','dec':'dex' if reg=='x' else 'dey'}
   changed=[];saving=0
   for line in code:
    m=re.match(r'^(\s*)(lda|sta|inc|dec)\s+'+re.escape(var)+r'\s*$',line)
    if m:
     changed.append(m[1]+mapping[m[2]])
     saving+=2
    elif re.match(r'^\s*jsr\s+\w+\s*$',line):
     changed.extend(['    st'+reg+' '+var,line,'    php','    ld'+reg+' '+var,'    plp'])
     saving-=8
    else:changed.append(line)
   entry=next((i for i,s in enumerate(changed) if s.endswith('_entry:')),None)
   if entry is None:continue
   changed.insert(entry+1,'    ld'+reg+' '+var);saving-=3
   candidates.append(dict(function=name,variable=var,register=reg,uses=n,calls=sum(op=='jsr' for _,op,_ in ops),predicted_saving=saving))
   if best is None or saving>best[0]:best=(saving,var,reg,changed)
 if best and best[0]>0:
  out.extend(best[3]);results.append(dict(function=name,variable=best[1],register=best[2],predicted_saving=best[0]))
 else:out.extend(code)
(P/'functions.asm').write_text('\n'.join(out)+'\n')
(P/'xy_home_stats.json').write_text(json.dumps(dict(selected=results,candidates=candidates),indent=2))
print('function-wide X/Y',len(results),'functions; estimated',sum(x['predicted_saving'] for x in results))
for x in results:print(x)
