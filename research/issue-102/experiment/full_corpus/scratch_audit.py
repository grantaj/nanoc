from pathlib import Path
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend,LocalArgumentBackend
from scratch_allocator import allocate
from execute6502 import relax
from collections import Counter
import json,re,csv
rows=[]
for p in sorted(Path('whole_corpus').glob('*.c')):
 if p.name=='ass.c':continue
 name=p.stem
 t=TapeBuilder(p.read_text()).build()
 arrays=json.loads(Path('whole_corpus/arrays.json').read_text())
 for which,Cls in [('local',LocalArgumentBackend),('cross',ArgumentPlacementBackend)]:
  b=Cls(t,arrays);code=b.run()
  ids=sorted(set(map(int,re.findall(r'__v(\d+)',code))))
  naive=sum(1 if t.values[x] in ('bool','u8') else 2 for x in ids)
  try:
   packed,metrics=allocate(t,b,code)
   rows.append(dict(name=name,planner=which,values=len(ids),naive_bytes=naive,packed_bytes=metrics['packed_bytes'],packed_zp_code_bytes=metrics['instruction_bytes'],status='ok'))
  except Exception as e:
   rows.append(dict(name=name,planner=which,values=len(ids),naive_bytes=naive,packed_bytes='',packed_zp_code_bytes='',status=str(e)))
for which in ('local','cross'):
 a=[x for x in rows if x['planner']==which]
 ok=[x for x in a if x['status']=='ok']
 print(which, 'packed passes',len(ok),'failed',len(a)-len(ok),'naive total static temps',sum(x['naive_bytes'] for x in a),'peak per-function temps',max(x['naive_bytes'] for x in a), 'max packed',max((x['packed_bytes'] for x in ok),default=0))
 print('blocked:',[(x['name'],x['status'][:64]) for x in a if x['status']!='ok'])
with open('whole_corpus/scratch_audit.csv','w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
