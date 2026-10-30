"""Exact 6502 machine-state shortest-path search for independent byte-copy runs.

This is a research test of state-directed, costed instruction selection, not a
peephole table: the search state is (completed semantic writes, A contents),
and each transition chooses the next independent store plus optional LDA.

Only accepts runs where all memory addresses are distinct across destinations,
no destination aliases any source, and the final A/NZ state matches the old
sequence.  Other instructions and all CFG edges are preserved exactly.
"""
from __future__ import annotations
from pathlib import Path
from collections import Counter
from functools import lru_cache
import json, os,re
R=Path(__file__).resolve().parent
GET=re.compile(r'^\s*lda\s+([^\s;,()]+)\s*$',re.I)
PUT=re.compile(r'^\s*sta\s+([^\s;,()]+)\s*$',re.I)
SYM=json.loads((R/'symbols.json').read_text())
ZP=json.loads((R/'layout.json').read_text())['zp']
SYM={**SYM,**ZP}

def addr(x):
    if x.startswith('#'):return None
    m=re.fullmatch(r'([\w]+)(\+1)?',x)
    if not m:return None
    a=SYM.get(m.group(1))
    if not isinstance(a,int):return None
    return (a+(1 if m.group(2) else 0))&65535

def cost(op,arg):
    if arg.startswith('#'):return 2
    a=addr(arg)
    if a is None:raise ValueError(arg)
    return 2 if a<256 else 3

def safe(pairs):
    if len(pairs)<2 or len(pairs)>12:return False
    sources=[addr(x) for x,y in pairs if not x.startswith('#')]
    dests=[addr(y) for x,y in pairs]
    if any(x is None for x in sources+dests):return False
    if len(dests)!=len(set(dests)) or set(dests).intersection(sources):return False
    # Distinct machine addresses, no volatile or processor registers, no input
    # buffer aliases.  Statically allocated C locals/arguments/globals only.
    return all(not (0xd000<=a<=0xdfff) for a in dests+sources)

def solve(pairs):
    """Return optimal state-path and exact byte cost; canonical tie-breaks."""
    sources=tuple(x for x,y in pairs); n=len(pairs); full=(1<<n)-1
    @lru_cache(None)
    def dp(mask,last):
        if mask==full:
            # Final A and NZ must be precisely the original last LDA's value.
            if last==sources[-1]:return (0,())
            return (cost('lda',sources[-1]),((-1,sources[-1]),))
        result=None
        for i,(src,dest) in enumerate(pairs):
            if mask>>i&1:continue
            costnext,path=dp(mask|1<<i,src)
            ld=cost('lda',src) if last!=src else 0
            cand=(ld+cost('sta',dest)+costnext,((i,src),)+path)
            if result is None or (cand[0],cand[1])<(result[0],result[1]):result=cand
        return result
    best,path=dp(0,None)
    seq=[];a=None
    for i,src in path:
        if src!=a:
            seq.append('    lda '+src);a=src
        if i>=0:seq.append('    sta '+pairs[i][1])
    old=sum(cost('lda',src)+cost('sta',dst) for src,dst in pairs)
    return seq,best,old,dp.cache_info().currsize

def transform(lines):
    out=[];i=0;stats=Counter();sites=[]
    while i<len(lines)-1:
        j=i; pairs=[]
        while j+1<len(lines):
            g=GET.fullmatch(lines[j]);h=PUT.fullmatch(lines[j+1])
            if not(g and h):break
            pairs.append((g.group(1),h.group(1)));j+=2
        if not safe(pairs):out.append(lines[i]);i+=1;continue
        result,best,old,states=solve(pairs)
        stats['candidate_runs']+=1;stats['explored_states']+=states
        if best<old:
            out+=result;stats['selected_runs']+=1;stats['pre_outlining_bytes_saved']+=old-best
            sites.append({'line':i,'moves':len(pairs),'old':old,'best':best,'states':states})
        else:out+=lines[i:j]
        i=j
    out+=lines[i:]
    return out,dict(stats),sites

if __name__=='__main__':
 inp=R/'functions.asm'
 s=inp.read_text().splitlines();new,stats,sites=transform(s)
 inp.write_text('\n'.join(new)+'\n')
 (R/'copy_state_search_result.json').write_text(json.dumps({'stats':stats,'sites':sites},indent=2))
 print('COPY STATE SEARCH',stats)
 print('top',sorted(sites,key=lambda x:-x['old']+x['best'])[:12])
