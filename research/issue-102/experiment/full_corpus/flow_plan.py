"""Experimental SECOND-PASS machine-flow planner over the existing typed tape.

This is a falsifiable end-to-end trial, NOT another edit to the inherited emitter.
Pass A proves the exact loop's induction/side effects/consumer relationships and
reports a machine-state contract. Pass B emits one code sequence from that plan.
When the proof fails, no recipe is emitted. No function-name dispatch.
"""
from dataclasses import dataclass
from backend import Backend

@dataclass(frozen=True)
class TableScanPlan:
    source: str
    length: str
    table: str
    candidate: str
    bound: int
    stride: int
    fold: str
    # Machine contract: X = stride*candidate+Y, Y=source position,
    # __ap=source pointer; candidate is live across every loop backedge.


def analyze(t, arrays, initialized, fold_semantics, readonly_arrays):
    """Require a *complete* side-effect-free fixed-stride table scan CFG.

    Match semantic value def/use and loop backedges, not function names.
    This first conservative version recognises a 3-column, short-circuit
    comparison of ASCII-folded input bytes against immutable A..Z table bytes.
    In particular, it refuses arbitrary calls or mutable table contents.
    """
    blocks={b.name:b for b in t.blocks}
    defs={o.result:o for b in t.blocks for o in b.ops if o.result>=0}
    if len(blocks)!=16 or len(t.blocks)!=16 or t.rtype!='s16':return None
    kinds={op:sum(x.code==op for b in t.blocks for x in b.ops) for op in ('read','call','return','store_index','store','branch')}
    if kinds!={'read':6,'call':3,'return':3,'store_index':0,'store':3,'branch':5}:return None
    entry=blocks.get('entry')
    if not entry or len(entry.ops)!=4 or entry.ops[-1].code!='branch':return None
    e0,e1,e2,ebr=entry.ops
    if not(e0.code=='load' and e1.code=='const' and e2.code=='!=' and
           e2.args==(e0.result,e1.result) and e1.args==(3,)):
        return None
    length=e0.args[0]
    if t.types.get(length)!='u8':return None
    # A value path must do exactly candidate=0; unconditional jump into header.
    starts=[]
    for b in t.blocks:
        if len(b.ops)==3 and b.ops[0].code=='const' and b.ops[0].args==(0,) and \
           b.ops[1].code=='store' and b.ops[1].args[1]==b.ops[0].result and b.ops[2].code=='jump':
            starts.append(b)
    if len(starts)!=1:return None
    start=starts[0];candidate=start.ops[1].args[0]
    if t.types.get(candidate)!='u8':return None
    hdr=blocks.get(start.ops[-1].args[0]);
    if not hdr or len(hdr.ops)!=4:return None
    hi,hb,hcmp,hbranch=hdr.ops
    if not(hi.code=='load' and hi.args==(candidate,) and hb.code=='const' and
           hcmp.code=='<' and hcmp.args==(hi.result,hb.result) and
           hbranch.code=='branch' and hbranch.args[0]==hcmp.result):return None
    bound=hb.args[0]
    if not isinstance(bound,int) or not 0<bound<=85:return None
    body=blocks.get(hbranch.args[1]);exitb=blocks.get(hbranch.args[2])
    if not body or len(body.ops)!=13 or not exitb or exitb.ops[-1].code!='return':return None
    cb,mul,prod,offset_store=body.ops[:4]
    if not(cb.code=='load' and cb.args==(candidate,) and mul.code=='const' and
           prod.code=='*' and prod.args==(cb.result,mul.result) and
           offset_store.code=='store' and offset_store.args[1]==prod.result):return None
    stride=mul.args[0];offset=offset_store.args[0]
    if stride!=3 or t.types.get(offset)!='u8':return None
    # Three comparison branches, chained through their successful edges.
    cmpblocks=[];b=body
    for j in range(stride):
        if b is None or not b.ops or b.ops[-1].code!='branch':return None
        br=b.ops[-1];cmp=defs.get(br.args[0]);
        if cmp is None or cmp.code!='==':return None
        left,right=(defs.get(v) for v in cmp.args)
        if left is None or right is None:return None
        if left.code!='call' or right.code!='read':return None
        if len(left.args)!=2 or left.args[0] not in fold_semantics:return None
        fold=left.args[0]
        text_read=defs.get(left.args[1]);
        if not text_read or text_read.code!='read':return None
        basetext,offtext=(defs.get(v) for v in text_read.args)
        if not(basetext.code=='load' and offtext.code=='const' and offtext.args==(j,)):
            return None
        source=basetext.args[0]
        if t.types.get(source)!='ptr':return None
        table_base,table_index=(defs.get(v) for v in right.args)
        if not table_base or table_base.code!='load':return None
        table=table_base.args[0]
        if table not in arrays or arrays[table][0]!='u8':return None
        if j==0:
            if not(table_index.code=='load' and table_index.args==(offset,)):return None
        else:
            if table_index.code!='+':return None
            x,y=(defs.get(v) for v in table_index.args)
            if not(x.code=='load' and x.args==(offset,) and y.code=='const' and y.args==(j,)):
                return None
        cmpblocks.append((b,br,source,table,fold))
        if j<stride-1:b=blocks.get(br.args[1])
    if len({x[2] for x in cmpblocks})!=1 or len({x[3] for x in cmpblocks})!=1 or len({x[4] for x in cmpblocks})!=1:return None
    source,table,fold=cmpblocks[0][2:]
    # Last successful path must return the scanned candidate.
    yes=blocks.get(cmpblocks[-1][1].args[1]);
    if not yes or len(yes.ops)!=2 or yes.ops[0].code!='load' or yes.ops[0].args!=(candidate,) or \
       yes.ops[1].code!='return' or yes.ops[1].args!=(yes.ops[0].result,):return None
    # All failures should lead through simple empty jumps to ONE increment latch.
    mismatch_targets=[x[1].args[2] for x in cmpblocks]
    tails=[]
    for m in mismatch_targets:
        visited=set()
        while m in blocks and m not in visited and len(blocks[m].ops)==1 and blocks[m].ops[0].code=='jump':
            visited.add(m);m=blocks[m].ops[0].args[0]
        tails.append(m)
    if len(set(tails))!=1:return None
    latch=blocks.get(tails[0]);
    if not latch or len(latch.ops)!=5:return None
    a,one,addition,store,jump=latch.ops
    if not(a.code=='load' and a.args==(candidate,) and one.code=='const' and one.args==(1,) and
           addition.code=='+' and addition.args==(a.result,one.result) and
           store.code=='store' and store.args==(candidate,addition.result) and
           jump.code=='jump' and jump.args==(hdr.name,)):return None
    # The only other stores must be candidate initialization and offset.
    stores=[o for b in t.blocks for o in b.ops if o.code=='store']
    if {o.args[0] for o in stores}!={candidate,offset}:return None
    # The generic C tape has no indirect memory writes; all calls are the
    # equivalent proven ASCII fold. The table MUST be immutable and uppercase.
    data=initialized.get(table)
    if data is None or table not in readonly_arrays or len(data)<bound*stride:return None
    if any(not(65<=n<=90) for n in data[:bound*stride]):return None
    # Folding only needs equality against A..Z: f(c)==T iff c&0xdf==T
    # for all c in 0..255, proved exhaustively for each specified helper.
    f=fold_semantics[fold]
    if any((f[c]==target)!=((c&0xdf)==target) for c in range(256) for target in range(65,91)):
        return None
    # Detect no extra semantic effects or opaque operations on visited paths.
    # The complete 16-block shape plus kinds/counters prevents skipped work.
    if len(set(o.result for b in t.blocks for o in b.ops if o.result>=0))!=t.nextvalue:return None
    return TableScanPlan(source,length,table,candidate,bound,stride,fold)


class FlowPlanBackend(Backend):
    def __init__(self,t,arrays,initialized,fold_semantics,readonly_arrays=()):
        super().__init__(t,arrays)
        self.plan=analyze(t,arrays,initialized,fold_semantics,readonly_arrays)
        self.decisions={}

    def run(self):
        if self.plan is None:raise ValueError('no verified machine-flow plan')
        p=self.plan
        if p.bound*p.stride>255:raise ValueError('X-indexed table would wrap')
        self.lines=[]
        self.mark('entry')
        self.emit('lda',p.length);self.emit('cmp','#$%02x'%p.stride)
        self.emit('bne','__flow_miss_exit')
        self.emit('lda',p.source);self.emit('sta','__ap')
        self.emit('lda',p.source+'+1');self.emit('sta','__ap+1')
        self.emit('lda','#$00');self.emit('sta',p.candidate)
        self.emit('ldx','#$00')
        self.mark('__flow_candidate')
        self.emit('ldy','#$00')
        self.mark('__flow_compare')
        self.emit('lda','(__ap),y');self.emit('and','#$df')
        self.emit('cmp',p.table+',x');self.emit('bne','__flow_skip')
        self.emit('iny');self.emit('inx');self.emit('cpy','#$%02x'%p.stride)
        self.emit('bne','__flow_compare')
        self.emit('lda',p.candidate);self.emit('ldx','#$00');self.emit('rts')
        self.mark('__flow_skip')
        self.emit('inx');self.emit('iny');self.emit('cpy','#$%02x'%p.stride)
        self.emit('bne','__flow_skip')
        self.emit('inc',p.candidate);self.emit('lda',p.candidate)
        self.emit('cmp','#$%02x'%p.bound);self.emit('bcc','__flow_candidate')
        self.mark('__flow_miss_exit')
        self.emit('lda','#$ff');self.emit('ldx','#$ff');self.emit('rts')
        self.decisions['planned_fixed_stride_table_scan']=1
        return '\n'.join(self.lines)+'\n'


def pure_byte_summaries(sourcedir):
    """Second-pass callee summaries: exhaust *all* 256 inputs of pure byte funcs.

    This is exact in the restricted typed-tape semantics because there are only
    256 possible byte arguments. No helper name or fold pattern is hard-coded.
    """
    from pathlib import Path
    from tape_frontend import TapeBuilder
    from tape_vm import VM
    out={}
    for path in Path(sourcedir).glob('*.c'):
        # The corpus has one function per input file and common declarations.
        t=TapeBuilder(path.read_text()).build()
        if t.rtype!='u8':continue
        args=t.fn.decl.type.args.params if t.fn.decl.type.args else []
        if len(args)!=1 or t.types.get(args[0].name)!='u8':continue
        if any(o.code in ('call','store','store_index','read') or
               (o.code=='load' and o.args[0]!=args[0].name)
               for b in t.blocks for o in b.ops):continue
        try:
            outcomes=tuple(VM(t,{args[0].name:x}).run()[0] for x in range(256))
        except (ValueError,TimeoutError,NotImplementedError):continue
        out[t.fn.decl.name]=outcomes
    return out


def prove_readonly_arrays(sourcedir, arrays):
    """Whole-program escape check for initialized table arrays on typed tape.

    An array address may only be consumed by a direct read from that same
    array. Any store_index, call, return or alias use rejects the table.
    This is deliberately conservative; it is a semantic proof in our
    restricted C subset, not a general C alias analysis.
    """
    from pathlib import Path
    from tape_frontend import TapeBuilder
    from scratch_allocator import sources
    safe=set(arrays)
    for path in Path(sourcedir).glob('*.c'):
        t=TapeBuilder(path.read_text()).build()
        defs={op.result:op for b in t.blocks for op in b.ops if op.result>=0}
        array_loads={v:o.args[0] for v,o in defs.items()
                     if o.code=='load' and o.args[0] in arrays}
        for b in t.blocks:
            for o in b.ops:
                for v in sources(o,defs) & array_loads.keys():
                    if o.code!='read' or o.args[0]!=v:
                        safe.discard(array_loads[v])
                if o.code=='store' and o.args[0] in arrays:safe.discard(o.args[0])
    return safe
