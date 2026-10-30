"""Research alternative: exact, effect-preserving 6502 instruction outlining.

Factor repeated straight-line, label-free instruction sequences into subroutines.
This is code size selection, not a register cache.  No function/variable names
are hardcoded.  JSR/RTS leave register/flags unchanged and give the exact
instruction semantics when no operand observes the hardware stack.
"""
from collections import defaultdict
from pathlib import Path
import re,json,sys
from build_image import Assembler,R
file=R/'functions.asm';boot=R/'boot.asm'
raw=file.read_text().splitlines()
# Read machine operand sizes with the exact same assembler used by the linker.
a=Assembler((R/'unoptimized.asm').read_text())
symbols=json.loads((R/'symbols.json').read_text())
a.symbols={**symbols, **json.loads((R/'compact_resolved.json').read_text())}
stop={'jsr','jmp','rts','rti','brk','bne','beq','bcc','bcs','bmi','bpl','bvc','bvs','pha','pla','php','plp','tsx','txs'}
# The specific compiler does not use observable hardware stack access.
assert not any(re.search(r'\b(?:pha|pla|php|plp|tsx|txs)\b|\$01[0-9a-f]{2}',x,re.I) for x in raw)
size={}
for x in raw:
 if not x.startswith('    ') or not x.strip():continue
 s=x.strip()
 if s.startswith(('byte ','word ')):continue
 op=s.split()[0]
 if op in stop:continue
 if s not in size:size[s]=a.instruction(s,False)[1]

# Greedy maximal savings over repeated identical instructions, bounded to
# straight-line control-flow regions and never crossing symbol definitions.
def all_runs(lines):
 runs=[];one=[]
 for i,x in enumerate(lines):
  s=x.strip();ok=x.startswith('    ') and s and s.split()[0] not in stop and not s.startswith(('byte ','word '))
  if ok:one.append((i,s))
  else:
   if one:runs.append(one);one=[]
 if one:runs.append(one)
 return runs

def candidates(lines):
 occ=defaultdict(list)
 for block in all_runs(lines):
  for i in range(len(block)):
   cumulative=0
   for j in range(i,min(len(block),i+36)):
    cumulative+=size[block[j][1]]
    if j-i+1<4 or cumulative<9:continue
    key=tuple(x[1] for x in block[i:j+1]);occ[key].append((block[i][0],block[j][0]+1))
 out=[]
 for key,positions in occ.items():
  if len(positions)<2:continue
  positions.sort();accepted=[];end=-1
  for l,r in positions:
   if l>=end:accepted.append((l,r));end=r
  if len(accepted)<2:continue
  bytes_=sum(size[x] for x in key)
  savings=len(accepted)*(bytes_-3) -(bytes_+1) # JSR 3B, helper RTS 1B
  if savings>=8:out.append((savings,bytes_,key,accepted))
 return sorted(out,key=lambda o:(o[0],o[1]),reverse=True)

chosen=[]
for i in range(150):
 opts=candidates(raw)
 if not opts:break
 savings,nbytes,key,positions=opts[0]
 name='__outline_%02d'%(len(chosen)+1)
 for l,r in sorted(positions,reverse=True):raw[l:r]=['    jsr '+name]
 chosen.append((name,savings,nbytes,len(positions),key))
 print(name,'gross',savings,'orig',nbytes,'occurrences',len(positions))
file.write_text('\n'.join(raw)+'\n')
boot.write_text(boot.read_text().rstrip()+'\n'+'\n'.join(name+':\n'+'\n'.join('    '+x for x in key)+'\n    rts' for name,*_,key in chosen)+'\n')
(R/'outline_stats.json').write_text(json.dumps({'count':len(chosen),'nominal_bytes_saved':sum(x[1] for x in chosen),'details':[{'helper':name,'nominal_saving':saving,'sequence_bytes':nbytes,'occurrences':occ,'instructions':list(key)} for name,saving,nbytes,occ,key in chosen]},indent=2))
print('TOTAL',len(chosen),'estimated',sum(x[1] for x in chosen))
