"""Research #102: bounded shortest-path/beam search for 6502 basic-block layout.

Input is already validated 6502 code from the typed tape.  This changes only
layout and branch fallthroughs; it neither changes data operations nor invents
function-name rules.  Edges are derived from the actual machine terminators.

Every reordering is a permutation of explicit labelled basic blocks; missing
fallthrough edges are made explicit.  Local branch targets are checked with an
assembler-width conservative safety margin.  The outer physical linker is the
final correctness oracle.  The original order is retained if not improved.
"""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
from collections import Counter
import json, os, re, random

R=Path(__file__).resolve().parent
FUNC_NAMES=[r['name'] for r in json.loads((R/'sizes.json').read_text())]
BRANCH={'beq','bne','bcc','bcs','bmi','bpl','bvc','bvs'}
INVERT={'beq':'bne','bne':'beq','bcc':'bcs','bcs':'bcc','bmi':'bpl','bpl':'bmi','bvc':'bvs','bvs':'bvc'}
LABEL=re.compile(r'^([A-Za-z_][A-Za-z_0-9]*):$')
INSTRUCTION=re.compile(r'^\s*([a-z]{3})(?:\s+([^;]+?))?\s*$',re.I)

@dataclass
class Block:
    labels:tuple[str,...]
    instructions:tuple[str,...]
    original:int=0
    original_fallthrough:str|None=None
    @property
    def name(self):return self.labels[0]

def decode(line):
    m=INSTRUCTION.match(line)
    return (m.group(1).lower(),(m.group(2) or '').strip()) if m else ('','')

def parse_func(lines):
    """Return movable code blocks, fixed trailing string data, plus function name."""
    func=LABEL.match(lines[0]).group(1)
    data_at=next((i for i,s in enumerate(lines) if s.strip().startswith(('byte ','word '))),len(lines))
    # Back up through leading labels of first data item.
    if data_at<len(lines):
        i=data_at-1
        while i>0 and LABEL.match(lines[i]): i-=1
        data_at=i+1
    code=lines[:data_at]
    chunks=[];labels=[];instructions=[]
    def flush():
        nonlocal labels,instructions
        if labels:chunks.append(Block(tuple(labels),tuple(instructions),len(chunks)))
        labels=[];instructions=[]
    for line in code:
        m=LABEL.match(line)
        if m:
            if instructions:flush()
            labels.append(m.group(1))
        else:
            if not labels: raise ValueError('code before label in '+func)
            instructions.append(line)
    flush()
    # Identify original implicit fallthroughs, including conditionals.
    for i,b in enumerate(chunks):
        if not b.instructions:continue
        op,arg=decode(b.instructions[-1]);ft=chunks[i+1].name if i+1<len(chunks) else None
        if op not in ('rts','rti','jmp','brk'):
            b.original_fallthrough=ft
        if b.original_fallthrough is None and op not in ('rts','rti','jmp','brk'):
            raise ValueError('function fallthrough into strings or next fn: '+func+' '+b.name)
    return func,chunks,lines[data_at:]

def targets(b):
    ins=[decode(s) for s in b.instructions if decode(s)[0]]
    if not ins:return []
    last=ins[-1];out=[]
    if last[0]=='jmp':out.append(last[1])
    if last[0] in BRANCH:out.append(last[1])
    if b.original_fallthrough:out.append(b.original_fallthrough)
    # The next-to-last conditional branch is a second CFG successor.
    if len(ins)>1 and ins[-1][0]=='jmp' and ins[-2][0] in BRANCH:out.append(ins[-2][1])
    return out

def benefit(a,b):
    ins=[decode(s) for s in a.instructions if decode(s)[0]]
    if not ins:return 0
    op,arg=ins[-1]
    if op=='jmp':
        if arg==b.name or arg in b.labels:return 3
        if len(ins)>=2 and ins[-2][0] in BRANCH and ins[-2][1] in b.labels:return 3
    if a.original_fallthrough in b.labels:return 3
    return 0

def emit_block(b,next_name):
    out=[l+':' for l in b.labels]
    lines=list(b.instructions)
    ins=[decode(s) for s in lines if decode(s)[0]]
    if ins:
        op,arg=ins[-1]
        if op=='jmp' and next_name in (arg,):
            lines=lines[:-1]
        elif op=='jmp' and len(ins)>=2 and ins[-2][0] in BRANCH and ins[-2][1]==next_name:
            # Branch inversion preserves flags and both exact successors.
            op2,arg2=ins[-2]
            lines=lines[:-2]+['    '+INVERT[op2]+' '+arg]
        elif b.original_fallthrough and b.original_fallthrough!=next_name:
            lines.append('    jmp '+b.original_fallthrough)
    out.extend(lines)
    return out

def operand_width(line):
    op,arg=decode(line)
    if not op:return 0
    if op in BRANCH or arg.startswith('#'):return 2
    if op in ('jmp','jsr'):return 3
    if not arg or arg.lower()=='a':return 1
    # Upper-bound conservatively treats all direct operands as absolute.
    if arg.startswith('('):return 3
    return 3

def branches_near(order,blocks,limit=109):
    """Conservative intra-function branch reachability test (final linker checks exact)."""
    out=[]
    for j,k in enumerate(order):
        name=blocks[order[j+1]].name if j+1<len(order) else None
        out+=emit_block(blocks[k],name)
    addr=0;symbols={};sites=[]
    for line in out:
        match=LABEL.match(line)
        if match:symbols[match.group(1)]=addr;continue
        op,arg=decode(line)
        if op in BRANCH:sites.append((addr,arg))
        addr+=operand_width(line)
    for pos,name in sites:
        if name in symbols and abs(symbols[name]-(pos+2))>limit:
            return False
    return True

def search_order(blocks,beam_size=48,lookahead=5):
    n=len(blocks);names={name:i for i,b in enumerate(blocks) for name in b.labels}
    if n<=2:return list(range(n)),dict(states=1,accepted=0)
    # Every non-entry block may follow any predecessor.  Model each placement as
    # an edge with its saved-JMP cost, yielding a shortest-path/ATSP-style search.
    edges=[[benefit(a,b) if i!=j else -999 for j,b in enumerate(blocks)] for i,a in enumerate(blocks)]
    # Basic blocks that have several labels are preserved as one unit.
    # The beam keeps alternative orders with distinct last-state/endpoints.
    start=(0,1, (0,),0.0) # score, mask, order, locality penalty
    beam=[start];states=0
    for depth in range(1,n):
        best={};end_options=range(1,n)
        for reward,mask,path,penalty in beam:
            last=path[-1]
            for j in end_options:
                if mask>>j&1:continue
                states+=1
                r=reward+edges[last][j]
                # Prefers nearby original blocks when no fallthrough is won;
                # avoids large branch displacements and search degeneracy.
                p=penalty+min(40,abs(j-last)-1)*0.012
                newpath=path+(j,)
                key=(mask|1<<j,j)
                candidate=(r,mask|1<<j,newpath,p)
                old=best.get(key)
                if old is None or (r-p,-p,newpath)>(old[0]-old[3],-old[3],old[2]):best[key]=candidate
        if not best:break
        # Bound on remaining potential savings from each node's outgoing edges;
        # this is a beam heuristic, never a correctness assumption.
        vals=list(best.values())
        vals.sort(key=lambda c:(c[0]-c[3]+ min(n-depth-1, sum(1 for k in range(n) if not(c[1]>>k&1)))*1.3, c[0]-c[3]),reverse=True)
        beam=vals[:beam_size]
    candidates=beam+[(sum(edges[i][i+1] for i in range(n-1)),(1<<n)-1,tuple(range(n)),0)]
    candidates.sort(key=lambda c:c[0]-c[3],reverse=True)
    original=list(range(n));count=0
    for reward,mask,path,penalty in candidates:
        count+=1
        if branches_near(path,blocks):return list(path),dict(states=states,accepted=count,score=reward)
    return original,dict(states=states,accepted=count,score=sum(edges[i][i+1] for i in range(n-1)),fallback=True)

def transform(lines,beam_size=48):
    starts=[(i,m.group(1)) for i,line in enumerate(lines) if (m:=LABEL.match(line)) and m.group(1) in FUNC_NAMES]
    assert len(starts)==44,(len(starts),starts[:5])
    starts.append((len(lines),None))
    result=[];stats={};grand=Counter()
    for (start,name),(end,_) in zip(starts,starts[1:]):
        allowed=set(os.environ.get('BLOCK_ONLY','').split(',')) if os.environ.get('BLOCK_ONLY') else None
        if allowed is not None and name not in allowed:
            result.extend(lines[start:end]);continue
        fn,blocks,trailing=parse_func(lines[start:end]);original=list(range(len(blocks)))
        # A movable region cannot be entered by another function except entry.
        if any(b.name.startswith('__S_') for b in blocks):raise RuntimeError('string parsed as code')
        found,search=search_order(blocks,beam_size)
        b={name:v for v in blocks for name in v.labels}
        # Do not select a layout solely for aggregate estimated benefit: it
        # must pass the conservative branch-range proof.
        oldcode=sum(operand_width(x) for x in lines[start:end] if decode(x)[0])
        newcode=[]
        for j,k in enumerate(found):
            next_name=blocks[found[j+1]].name if j+1<len(found) else None
            newcode.extend(emit_block(blocks[k],next_name))
        newcode.extend(trailing)
        newbytes=sum(operand_width(x) for x in newcode if decode(x)[0]);gain=oldcode-newbytes
        # Avoid reordering on zero/negative estimated gain.  All labels and
        # instructions must remain present (save erased JMPs and inversions).
        if gain>0 and branches_near(found,blocks):
            result.extend(newcode);grand['accepted_functions']+=1;grand['gross_estimated_bytes']+=gain
        else:
            result.extend(lines[start:end]);grand['rejected_functions']+=1
        stats[fn]={**search,'blocks':len(blocks),'old_estimated':oldcode,'new_estimated':newbytes,
                   'accepted':gain>0 and branches_near(found,blocks),'saved_estimated':max(0,gain) if branches_near(found,blocks) else 0,'reordered':found!=original and gain>0 and branches_near(found,blocks)}
        grand['explored_states']+=search['states']
    return result,{'grand':dict(grand),'functions':stats}

if __name__=='__main__':
 import sys
 inp=R/'functions.asm';original=inp.read_text().splitlines()
 new,report=transform(original,beam_size=int(os.environ.get('BLOCK_BEAM','48')))
 inp.write_text('\n'.join(new)+'\n')
 (R/'block_order_search_results.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(report['grand'],indent=2))
 print('top estimated',sorted(((k,v['saved_estimated'],v['blocks']) for k,v in report['functions'].items()),key=lambda x:-x[1])[:16])
