"""Use exact host-built bootstrap/ass.c to assemble each emitted 6502 function.
External globals/call targets are synthetic symbols only; NOT a linked C64 binary.
"""
from pathlib import Path
import re,subprocess,csv
from execute6502 import relax
import link_audit
ROOT=Path(__file__).parent
shorts={'__ap':0x10,'__ix':0x12,'__rh':0x14,'__mw':0x15}
results=[]
for file in sorted((ROOT/'whole_corpus').glob('*.cross.asm')):
 fn=file.name.split('.cross.asm')[0]
 lines=link_audit.lines_by_fn[fn]
 known={x.strip()[:-1] for x in lines if x.strip().endswith(':')}
 symbols=set()
 for line in lines:
  s=line.strip()
  if not s or s.endswith(':'):continue
  op,_,arg=s.partition(' ')
  arg=arg.strip()
  if not arg:continue
  arg=arg.replace(',y','').replace(',x','').replace('(','').replace(')','')
  if arg[0:1]=='#':arg=arg[1:]
  if arg[0:1] in '<>':arg=arg[1:]
  if arg.startswith('$'):continue
  if re.fullmatch(r'\d+',arg):continue
  if re.fullmatch(r'[a-zA-Z_][a-zA-Z_0-9]*(\+\d+)?',arg):
   stem=arg.split('+')[0]
   if stem not in known:symbols.add(stem)
  else:raise ValueError((fn,line))
 zppos=0x20
 defs=[];others=[]
 for name in sorted(symbols):
  if name in shorts:defs.append((name,shorts[name]))
  elif name.startswith('__tmp'):
   defs.append((name,zppos));zppos+=1
  else:others.append(name)
 for i,name in enumerate(others):defs.append((name,0x4000+2*i))
 if len(others)>3000:raise RuntimeError('too many symbols')
 f=ROOT/'whole_corpus'/(fn+'.strict.asm')
 f.write_text('* = $0800\n' + ''.join(name+' = $%04x\n'%a for name,a in defs) + '\n'.join(lines)+'\n')
 r=subprocess.run([str(ROOT/'host_assembler'),str(f.relative_to(ROOT))],cwd=ROOT,text=True,capture_output=True)
 expected=int(next(x for x in csv.DictReader(open(ROOT/'whole_corpus'/'coverage.csv')) if x['name']==fn)['cross_bytes'])
 m=re.search(r'assembled (\d+) bytes',r.stdout)
 actual=int(m.group(1)) if m else 0
 results.append(dict(name=fn,baseline_estimate=expected,strict_assembled=actual,ok=int(r.returncode==0 and actual==expected),error=(r.stderr or r.stdout)[:120] if r.returncode or actual!=expected else ''))
 print('%-32s expected=%4d strict=%4d status=%3d %s'%(fn,expected,actual,r.returncode,(r.stderr or '')[:100].strip()),flush=True)
with open(ROOT/'whole_corpus'/'strict_results.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(results[0]));w.writeheader();w.writerows(results)
print('STRICT SUCCESS',sum(x['ok'] for x in results),'/',len(results))
