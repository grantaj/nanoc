"""Differential and optimality tests for exact instruction-copy state search."""
import random,itertools
from copy_state_search import solve,safe,addr,cost,SYM

rng=random.Random(20261030)
addresses=[]
for k,v in SYM.items():
    if isinstance(v,int) and v not in addresses and not 0xd000<=v<=0xdfff:
        addresses.append(v)
addr_names={v:k for k,v in SYM.items() if v in addresses}
# Restrict to immutable-looking BSS homes: the tests initialize all chosen
# source bytes as explicit snapshots, and no destination may alias a source.
addresses=[x for x in addresses if 0x4800<=x<0xc000]

def execute(lines, initial):
    mem=initial.copy();a=0;z=0;n=0;c=1;v=1
    for line in lines:
        op,x=line.strip().split()
        if op=='lda':
            a=(int(x[2:],16) if x.startswith('#$') else mem[addr(x)])&255
            z=int(a==0);n=(a>>7)&1
        elif op=='sta':mem[addr(x)]=a
        else:raise AssertionError(line)
    return (mem,a,z,n,c,v)

count=0;states=0
for width in range(2,8):
    for repeat in range(150):
        selected=rng.sample(addresses,width+3)
        srcp=[addr_names[k] for k in selected[:3]]
        dstp=[addr_names[k] for k in selected[3:]]
        srcs=[rng.choice(srcp+['#$00','#$01','#$7f','#$ff']) for _ in range(width)]
        pairs=list(zip(srcs,dstp))
        assert safe(pairs)
        new,best,old,num=solve(pairs)
        assert best<=old,(pairs,old,best)
        original=[s for source,dest in pairs for s in ('    lda '+source,'    sta '+dest)]
        mem={k:rng.randrange(256) for k in selected}
        assert execute(original,mem)==execute(new,mem),(pairs,new)
        count+=1;states+=num
        if width<=5 and repeat<10:
            # Independent brute-force check of the shortest-path optimum.
            brute=old
            for order in itertools.permutations(range(width)):
                a=None;cost_=0
                for i in order:
                    src,dst=pairs[i]
                    if src!=a:cost_+=cost('lda',src)
                    cost_+=cost('sta',dst);a=src
                if a!=pairs[-1][0]:cost_+=cost('lda',pairs[-1][0])
                brute=min(brute,cost_)
            assert brute==best,(pairs,brute,best)
# Explicitly exclude alias hazards and repeated destination side effects.
assert not safe([('src','dst'),('dst','src')])
known=[addr_names[a] for a in addresses[:3]]
assert not safe([(known[0],known[1]),(known[2],known[1])])
assert not safe([(known[0],known[1]),(known[1],known[2])])
print('PASS',count,'differential register/flag/memory executions;',states,'explored DP states, plus brute-force optimality and alias refusals')
