"""Semantics-preserving final code layout for the experimental physical image.
Only removes jumps to the next machine location or replaces
  Bcond L_true; JMP L_false; L_true: with Bnotcond L_false; L_true:
when an exact-layout displacement certificate fits the signed 8-bit branch.
"""
from pathlib import Path
from collections import Counter
from build_image import Assembler,original,R
import re,struct,json
INV={'bcc':'bcs','bcs':'bcc','beq':'bne','bne':'beq','bmi':'bpl','bpl':'bmi','bvc':'bvs','bvs':'bvc'}
lines=original.splitlines()
# A store does not change A.  A following load of the *same exact byte*
# reconstructs no value.  Elide it only if the immediately following
# instruction overwrites NZ before any flag consumer: CMP/EOR/LDX.
# This is an ABI-independent local equivalence, unlike speculative liveness.
removed_reload=0
for i in range(len(lines)-2,-1,-1):
    m=re.fullmatch(r'\s*sta\s+([^ ;]+)\s*',lines[i],re.I)
    n=re.fullmatch(r'\s*lda\s+([^ ;]+)\s*',lines[i+1],re.I)
    if m and n and m.group(1)==n.group(1) and i+2<len(lines):
        target=lines[i+2].strip().lower().split()
        if target and target[0] in ('cmp','eor','ldx'):
            lines.pop(i+1);removed_reload+=1
print('verified duplicate A reloads',removed_reload)
def nonempty(line):return line.strip().split(';')[0].strip()
def immediate_labels(lines,i):
 names=[];j=i+1
 while j<len(lines):
  s=nonempty(lines[j])
  if not s:j+=1;continue
  if s.endswith(':'):names.append(s[:-1]);j+=1;continue
  break
 return names,j

def line_addresses(lines):
 asm=Assembler('\n'.join(lines)+'\n')
 start,blob,symbols,counts=asm.assemble()
 addr={};pc=start
 for i,line in enumerate(lines):
  s=nonempty(line)
  if not s:continue
  addr[i]=pc
  if s.startswith('*'):pc=asm.expr(s.split('=')[1],True);continue
  if s.endswith(':') or '=' in s and re.fullmatch(r'\S+\s*=\s*\S+',s):continue
  if s.startswith('byte '):pc+=len(s[5:].split(','));continue
  pc+=asm.instruction(s,True)[1]
 assert pc==start+len(blob),(pc,start,len(blob))
 return symbols,addr,len(blob)

results=Counter();rounds=[]
# Remove JMP to physically following label (any number of adjacent label aliases).
for iteration in range(12):
 changed=0
 for i in range(len(lines)-1,-1,-1):
  s=nonempty(lines[i]);m=re.fullmatch(r'jmp\s+(\w+)',s,re.I)
  if m and m.group(1) in immediate_labels(lines,i)[0]:
   lines.pop(i);results['jmp_fallthrough']+=1;changed+=1
 if not changed:break
 rounds.append(('fallthrough',changed))
print('fallthrough removed',results['jmp_fallthrough'])

# Invert conditional then jump over the fallthrough branch. Remove the JMP.
# Recalculate exact forward target displacement after each group.
for iteration in range(20):
 symbols,addrs,nbytes=line_addresses(lines)
 changed=0;new=[];i=0
 while i<len(lines):
  a=nonempty(lines[i]);m=re.fullmatch(r'(bcc|bcs|beq|bne|bmi|bpl|bvc|bvs)\s+(\w+)',a,re.I)
  if m and i+1<len(lines):
   nxt=nonempty(lines[i+1]);j=re.fullmatch(r'jmp\s+(\w+)',nxt,re.I)
   if j and m.group(2) in immediate_labels(lines,i+1)[0]:
    dest=j.group(1)
    target=symbols.get(dest)
    if target is not None:
     # Keep a conservative margin to accommodate other transformations
     # in this pass.  All actually emitted branches are checked at link.
     signed_delta=target-(addrs[i]+2)
     if -128<=signed_delta<=130:
      new.append('    '+INV[m.group(1).lower()]+' '+dest)
      i+=2;changed+=1
      continue
  new.append(lines[i]);i+=1
 lines=new;results['branch_fallthrough']+=changed
 rounds.append(('branch_inversion',iteration,changed))
 if not changed:break
 # After inversion more unconditional next jumps may become redundant.
 removed=0
 for i in range(len(lines)-1,-1,-1):
  s=nonempty(lines[i]);m=re.fullmatch(r'jmp\s+(\w+)',s,re.I)
  if m and m.group(1) in immediate_labels(lines,i)[0]:
   lines.pop(i);results['jmp_fallthrough']+=1;removed+=1
 if removed:rounds.append(('new-fallthrough',removed))
print('transforms',dict(results),rounds)
asm=Assembler('\n'.join(lines)+'\n');start,blob,symbols,counts=asm.assemble()
(R/'compact_image.prg').write_bytes(struct.pack('<H',start)+blob)
(R/'compact_image.asm').write_text('\n'.join(lines)+'\n')
(R/'compact_resolved.json').write_text(json.dumps(symbols,indent=2))
(R/'layout_metrics.json').write_text(json.dumps({'initial_bytes':line_addresses(original.splitlines())[2],'compact_bytes':len(blob),'saved':line_addresses(original.splitlines())[2]-len(blob),'budget':16384,'over_budget':len(blob)-16384,'transformations':dict(results),'rounds':rounds,'image_start':start,'image_end':start+len(blob)},indent=2))
print('FINAL',len(blob),'saved',line_addresses(original.splitlines())[2]-len(blob),'headroom',16384-len(blob),'BSS start',hex(0x4800))
