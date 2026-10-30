"""Independently execute native emitted find_symbol over wide table boundaries.

Mocks only scope_for_name (0 for ordinary, -2 for invalid) to isolate the
compiler's memory traversal; the complete linked assembler is tested separately.
"""
from pathlib import Path
import json,random
from natural6502_wide import Natural6502Wide
from execute6502 import CPU
D=Path(__file__).parent/'whole_corpus'
source=(D/'find_symbol.c').read_text()
code=Natural6502Wide(source,json.loads((D/'arrays.json').read_text())).run()
rng=random.Random(65022026)
passes=0
bases={'symbol_scope':0x4000,'symbol_name_length':0x4400,'symbol_name_offset':0x4800,'symbol_name_bytes':0x6000}
class NoTrace:
 def append(self,x):pass
for count in (0,1,2,10,128,255,257,300,896):
 names=[bytes(((i//256)%26+65,(i//26)%26+65,i%26+65,ord('Z'))) for i in range(count)]
 # distinct up to 896 except our code's 26-based second digit repeats every 676;
 # use first matching index as oracle regardless.
 scope=[rng.randrange(2) for _ in names]
 for target in (-1,0,count//2,count-1):
  if target>=count:continue
  key=names[target] if target>=0 else b'ZZZZ'
  want=next((i for i,n in enumerate(names) if n==key and scope[i]==0),-1)
  for addr in (0x30fa,0x3100):
   state={'__L_find_symbol_name':addr,'__L_find_symbol_length':len(key),'symbol_count':count}
   cpu=CPU(code,list(key),state,{'scope_for_name':lambda x:0},text_base=addr)
   cpu.bases.update(bases);cpu.trace=NoTrace()
   for i,n in enumerate(names):
    cpu.heap[bases['symbol_scope']+i]=scope[i]
    cpu.heap[bases['symbol_name_length']+i]=len(n)
    off=i*4
    cpu.heap[bases['symbol_name_offset']+2*i]=off&255
    cpu.heap[bases['symbol_name_offset']+2*i+1]=off>>8
    for j,c in enumerate(n):cpu.heap[bases['symbol_name_bytes']+off+j]=c
   got=cpu.run(max_steps=150000)[0]
   assert got==want&65535,(count,target,addr,got,want)
   passes+=1
print('PASS',passes,'whole C symbol-traversal machine executions across wide records/page boundaries')
