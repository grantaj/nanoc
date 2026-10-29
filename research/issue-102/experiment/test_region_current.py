from machine_verify import Machine, SYM
from random import Random
R=Random(72)

def word(cpu,a,v): cpu.poke_word(a,v&0xffff)
def run_one(count,match,length,pointer):
  cpu=Machine({});cpu.m[1]=0x36;cpu.PC=SYM['find_symbol']
  stop=SYM['__experiment_stop'];cpu.push((stop-1)>>8);cpu.push((stop-1)&255)
  word(cpu,SYM['__call_find_symbol_0'],pointer);cpu.write(SYM['__call_find_symbol_1'],length)
  cpu.A=length  # current last-char-in-A ABI
  word(cpu,SYM['symbol_count'],count)
  if length:cpu.m[pointer:pointer+length]=b'Q'*length
  for i in range(count):
    cpu.write(SYM['symbol_scope']+i,0)
    cpu.write(SYM['symbol_name_length']+i,length)
    word(cpu,SYM['symbol_name_offset']+2*i,i*length)
    p=SYM['symbol_name_bytes']+i*length
    if p+length>=65536:raise ValueError('name overflow')
    cpu.m[p:p+length]= b'Q'*length if i==match else (b'R'+b'Q'*(length-1)) if length else b''
  steps,_=cpu.run(max_steps=5_000_000)
  value=cpu.A|(cpu.X<<8)
  expected=(match if match>=0 else 65535)
  assert value==expected,(count,match,length,pointer,value,expected)
  return steps

cases=[]
for c in (0,1,2,17,128,256,258,490):
  for m in (-1,0,c-1):
    if m>=c and m!=-1:continue
    cases.append((c,m,3,0x06fd))
for length in (1,2,10,31,64):cases.append((18,17,length,0x06fd))
for c,m,l,p in cases:
 try:steps=run_one(c,m,l,p)
 except Exception as e:
  print('FAIL',c,m,l,hex(p),e,flush=True);raise
 print('PASS',c,m,l,hex(p),'instructions',steps,flush=True)
print('PASS total',len(cases))
