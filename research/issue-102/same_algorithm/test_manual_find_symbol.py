"""Machine-executed differential tests of exactly the C find_symbol algorithm.

Hand-coded candidate retains parallel arrays/16-bit indexes and original ABI.
Runs full compiled scope_for_name and the actual linked function, not a stub.
"""
from pathlib import Path
import random
import machine_verify as mv
SYM=mv.SYM
rng=random.Random(65022026)


def run(names,scopes,target,key,scope_val,at):
    cpu=mv.Machine({})
    cpu.m[1]=0x34 # expose all RAM below ROM, as experimental program boot does
    base=0x06fc if at else 0x0600
    cpu.poke_word(SYM['__L_find_symbol_name'],base)
    cpu.write(SYM['current_scope'],scope_val)
    cpu.poke_word(SYM['symbol_count'],len(names))
    for i,(name,scope) in enumerate(zip(names,scopes)):
        cpu.write(SYM['symbol_scope']+i,scope)
        cpu.write(SYM['symbol_name_length']+i,len(name))
        off=4*i
        cpu.poke_word(SYM['symbol_name_offset']+2*i,off)
        for j,v in enumerate(name): cpu.write(SYM['symbol_name_bytes']+off+j,v)
    for i,v in enumerate(key):cpu.write(base+i,v)
    cpu.A=len(key)
    sentinel=0x0740
    cpu.push((sentinel-1)>>8);cpu.push((sentinel-1)&255)
    cpu.PC=SYM['find_symbol']
    for k in range(500000):
        if cpu.PC==sentinel:break
        cpu.step()
    else:raise RuntimeError('timeout',len(names),target,key)
    got=cpu.A|(cpu.X<<8)
    if len(key)==0 or (key[:1]==b'.' and scope_val==0):want=65534
    else:
        wanted_scope=scope_val if key[:1]==b'.' else 0
        want=next((i for i,(n,s) in enumerate(zip(names,scopes)) if s==wanted_scope and len(n)==len(key) and n==key),65535)
    assert got==want,(len(names),target,key,scope_val,at,hex(got),hex(want))
    return k

n=0;cycles=0
for count in (0,1,2,16,127,255,256,257,512,895,896):
    names=[bytes((65+i//26//26,65+(i//26)%26,65+i%26,90)) for i in range(count)]
    scopes=[rng.randrange(2) for _ in names]
    for target in (-1,0,count//2,count-1):
        if target>=count:continue
        key=names[target] if target>=0 else b'ZZZZ'
        for at in (0,1):
            k=run(names,scopes,target,key,0,at);n+=1;cycles+=k
    if count<=257:
        for key,cur in ((b'',0),(b'.ABC',0),(b'.ABC',1),(b'ABC',1)):
            k=run(names,scopes,-1,key,cur,1);n+=1;cycles+=k
print('PASS',n,'machine executions against C algorithm,',cycles,'instructions; max count 896')
