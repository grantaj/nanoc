"""Independent semantic stress for backward byte demand and certified Y scan.
Tests compare 6502 instruction execution to an independently calculated oracle,
not merely assembly byte counts. Also checks conservative refusal of bad loops.
"""
import sys,random
from pathlib import Path
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT/'full_corpus'))
from tape_frontend import TapeBuilder
from execute6502 import CPU,relax
from y_loop import YLoopBackend
from read_compare import DirectReadCompareBackend
from const_fold import FoldedBackend
from width_demand import WidthDemandBackend
rng=random.Random(291029)
tests=0

def run(backend,source,globals_,arrays=None,arraydata=None):
    tape=TapeBuilder(source).build()
    b=backend(tape,arrays or {})
    asm,_,_=relax(b.run())
    cpu=CPU(asm,[],globals_,{})
    for a,values in (arraydata or {}).items():
        cpu.bases[a]=0x4000+list((arraydata or {}).keys()).index(a)*0x100
        for i,v in enumerate(values):cpu.heap[cpu.bases[a]+i]=v
    ret,mem,calls=cpu.run(max_steps=4000)
    return ret,b,asm

# Result width is char; source arithmetic is int. Check full 16-bit input domain.
for expr,op in [('a + b',lambda a,b:a+b),('a - b',lambda a,b:a-b),
                ('a * 10',lambda a,b:a*10),('(a << 4)',lambda a,b:a<<4),
                ('(a ^ b)',lambda a,b:a^b),('-a',lambda a,b:-a)]:
    src=f'char calculate(unsigned a, unsigned b) {{ return {expr}; }}'
    for i in range(180):
        a=rng.randrange(65536);b=rng.randrange(65536)
        ret,backend,asm=run(WidthDemandBackend,src,{'a':a,'b':b})
        assert ret==(op(a,b)&255),(expr,a,b,ret,op(a,b)&255)
        tests+=1
# Full-width results must not be narrowed.
for expr,op in [('a + b',lambda a,b:a+b),('a - b',lambda a,b:a-b),
                ('a * 10',lambda a,b:a*10),('(a << 4)',lambda a,b:a<<4)]:
    src=f'unsigned calculate(unsigned a, unsigned b) {{ return {expr}; }}'
    for i in range(100):
        a=rng.randrange(65536);b=rng.randrange(65536)
        ret,backend,asm=run(WidthDemandBackend,src,{'a':a,'b':b})
        assert ret==((op(a,b))&65535),(expr,a,b,ret,op(a,b)&65535)
        tests+=1

scan='''
char data_a[256];
char data_b[256];
int scan(char want, char want2) {
    int i;
    i = 0;
    while (i < 256) {
        if (data_a[i] == want) {
            if (data_b[i] == want2) {
                return i;
            }
        }
        i = i + 1;
    }
    return -1;
}
'''
arrays={'data_a':('u8',256),'data_b':('u8',256)}
for rep in range(410):
    a=[rng.randrange(256) for _ in range(256)]
    b=[rng.randrange(256) for _ in range(256)]
    w=rng.randrange(256);z=rng.randrange(256)
    expected=next((i for i in range(256) if a[i]==w and b[i]==z),-1)&65535
    result,be,asm=run(DirectReadCompareBackend,scan,{'want':w,'want2':z},arrays,{'data_a':a,'data_b':b})
    assert be.yplans and be.direct_emitted==2,(be.y_rejected,be.direct_emitted)
    assert result==expected,(rep,result,expected)
    tests+=1
# Deliberate matches at boundary, including 255 and zero; no-match full scan.
for target in (0,1,127,254,255,None):
    a=[0]*256;b=[1]*256
    if target is not None:a[target]=42;b[target]=24
    result,be,asm=run(DirectReadCompareBackend,scan,{'want':42,'want2':24},arrays,{'data_a':a,'data_b':b})
    assert result==((target if target is not None else -1)&65535)
    tests+=1

# Stress safety refusal. These should still lower with the fallback compiler,
# but they may not be assigned the narrower Y-only loop algorithm.
no_proofs=[
 ('short array',scan.replace('data_a[256]','data_a[200]'),{'data_a':('u8',200),'data_b':('u8',256)}),
 ('observable index after loop',scan.replace('return -1;','return i;'),arrays),
 ('call inside loop',scan.replace('i = i + 1;','sink(i); i = i + 1;').replace('int scan(char want, char want2)', 'int sink(int x); int scan(char want, char want2)'),arrays),
 ('write through array',scan.replace('i = i + 1;','data_a[i] = 7; i = i + 1;'),arrays),
 ('nonunit increment',scan.replace('i = i + 1;','i = i + 2;'),arrays),
 ('different loop bound',scan.replace('i < 256','i < 255'),arrays),
]
for label,source,arrs in no_proofs:
    be=YLoopBackend(TapeBuilder(source).build(),arrs)
    assert not be.yplans,(label,be.yplans)
    tests+=1
# Regression for a real correctness defect caught during the linked rebuild:
# a read's only explicit consumer can be a comparison while a *later CSE
# alias* still depends on its materialised storage. Such an origin must NOT
# be fused into A-only direct comparison lowering.
alias_src="char g[256]; char alias_test(char i) { if (g[i] != 0) { if (g[i] == 7) return 1; } return 0; }"
for case in range(360):
    index=rng.randrange(256)
    buf=[rng.randrange(256) for _ in range(256)]
    if case%3==0:buf[index]=7
    if case%3==1:buf[index]=0
    ret,b,asm=run(FoldedBackend,alias_src,{'i':index},{'g':('u8',256)},{'g':buf})
    assert b.read_alias and not(set(b.direct_reads)&set(b.read_alias.values()))
    assert ret==int(buf[index]==7),(case,ret,buf[index])
    tests+=1

# Constant arithmetic is canonicalized on the typed tape, not synthesized
# as runtime subtraction from zero or a multiply chain.
for expr,expected in [('-1',65535),('-2',65534),('-3',65533),('3 * 5',15),('(65535 + 2)',1),('(7 << 4)',112)]:
    result,be,asm=run(FoldedBackend,f'int calculate() {{ return {expr}; }}',{})
    assert result==expected,(expr,result,expected)
    assert be.constant_folds>=1,(expr,be.constant_folds)
    tests+=1

# Two-pointer byte scans against an independent reference; pointers cross pages
# and may overlap; no write or call should invalidate the held pointer bases.
source=(ROOT/'full_corpus'/'whole_corpus'/'same_text.c').read_text()
for case in range(720):
    n=rng.randrange(256)
    a=[rng.randrange(256) for _ in range(n+1)]
    b=a[:]
    if case%3==1 and n:
        b[rng.randrange(n)]=(b[0]+1)&255
    if case%3==2:b=a[:];mismatch=0
    al=n;bl=n if case%7 else (n+1)&255
    x=0x30fa if case%2 else 0x3078
    y=0x40fc if case%2 else 0x40ac
    tape=TapeBuilder(source).build()
    be=FoldedBackend(tape,{})
    assert len(be.dual_plans)==1
    asm,_,_=relax(be.run())
    cpu=CPU(asm,[],{'a':x,'b':y,'a_length':al,'b_length':bl},{})
    for i,byte in enumerate(a):cpu.heap[x+i]=byte
    for i,byte in enumerate(b):cpu.heap[y+i]=byte
    got,_,_=cpu.run(max_steps=30000)
    want=int(al==bl and a[:n]==b[:n])
    assert got==want,(case,n,al,bl,got,want)
    tests+=1
print(f'PASS: {tests} operation-level correctness and loop-proof/refusal tests')
