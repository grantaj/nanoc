"""Independent machine-level tests for wide-index reuse and return ABI.

The full linked candidate is executed at real symbol addresses, with inputs
in actual static parameter slots and returns through the real 6502 stack.
No source-function names are used by the code generator; they appear here
solely as test entry points and behavioural oracles.
"""
from machine_verify import Machine,SYM


def call(m,name,max_steps=50000):
    stop=0x0700
    ret=stop-1
    m.push(ret>>8);m.push(ret&255)
    m.PC=SYM[name]
    for i in range(max_steps):
        if m.PC==stop:return (m.A,m.X,i)
        m.step()
    raise RuntimeError(f'{name} timed out at {m.PC:04x}')

def mnew():
    m=Machine({})
    m.m[1]=0x36  # BASIC banked out; KERNAL and I/O visible
    m.X=0xa5     # test that callers do not assume a byte result clears X
    return m

count=0
for n in [0,1,127,255,256,511,638,639,640]:
    m=mnew()
    m.poke_word(SYM['fixup_count'],n)
    values={'kind':4,'stage':0x9a17,'symbol':0x1234,'addend':0xbeef,'prefix':2}
    for k,v in values.items():
        addr=SYM[f'__L_append_fixup_{k}']
        if k in ('kind','prefix'):m.write(addr,v)
        else:m.poke_word(addr,v)
    m.A=values['prefix']  # current last-char-in-A ABI
    a,x,steps=call(m,'append_fixup')
    if n>=640:
        assert a==11 and m.word(SYM['fixup_count'])==n,(n,a)
    else:
        assert a==0 and m.word(SYM['fixup_count'])==n+1,(n,a)
        for array,key,width in [('fixup_kind','kind',1),('fixup_stage','stage',2),
                                ('fixup_symbol','symbol',2),('fixup_addend','addend',2),
                                ('fixup_prefix','prefix',1)]:
            p=SYM[array]+n*width
            got=m.read(p) if width==1 else m.word(p)
            assert got==values[key],(n,array,got,values[key])
    count+=1

for n in [0,1,127,255,256,511,894,895,896]:
    m=mnew()
    m.poke_word(SYM['symbol_count'],n)
    m.poke_word(SYM['symbol_name_used'],0)
    m.write(SYM['current_scope'],0)
    source=0x0700
    name=b'abc'
    m.m[source:source+len(name)]=name
    for key,v,w in [('name',source,2),('length',3,1),('kind',2,1),('payload',0xbeef,2)]:
        p=SYM[f'__L_allocate_symbol_{key}']
        if w==1:m.write(p,v)
        else:m.poke_word(p,v)
    a,x,steps=call(m,'allocate_symbol',max_steps=50000)
    got=a|(x<<8)
    if n>=896:
        assert got==0xfffd,(n,got)
    else:
        assert got==n,(n,got)
        assert m.word(SYM['symbol_count'])==n+1
        assert m.word(SYM['symbol_name_offset']+n*2)==0
        assert m.read(SYM['symbol_name_length']+n)==3
        assert m.word(SYM['symbol_payload']+n*2)==0xbeef
        assert m.read(SYM['symbol_kind']+n)==2
        assert m.m[SYM['symbol_name_bytes']:SYM['symbol_name_bytes']+3]==name
    count+=1
print(f'PASS {count} full-machine 16-bit indexed-array/ABI boundary cases')
