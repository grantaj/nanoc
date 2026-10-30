"""A SECOND, deliberately small 6502 machine-state/recipe selector.

This is a research generator from the SAME typed tape; it does not inherit
any of the 20+ experimental optimisation backends. The plain semantic emitter
is used solely as a correctness fallback for operations without a proven
machine recipe. Candidate decisions occur BEFORE assembly, not as peepholes.

Current scope: direct memory operands with snapshot proofs, fused producer-store
regions, direct 6502 byte indexing and register/flag state for redundant loads.
Whole-loop cursor planning is NOT yet supported; report that limitation.
"""
from collections import Counter, defaultdict
from dataclasses import dataclass
from backend import Backend
from scratch_allocator import sources

@dataclass
class MachineState:
    a: object = None
    x: object = None
    y: object = None
    flags: object = None
    ptr0: object = None
    ptr1: object = None

class MachineStrategyBackend(Backend):
    def __init__(self, t, arrays=None):
        super().__init__(t, arrays)
        self.machine = MachineState()
        self.current_block = None
        self.current_pos = -1
        self.direct = set()
        self.fused = {}
        self.skip = set()
        self.decisions = Counter()
        self.address_hits = self.index_hits = 0
        self._plan(t)
        self.scan_plan = self._find_scan_plan(t)

    def _plan(self,t):
        refs=defaultdict(list);defs={}
        for b in t.blocks:
            if b.name not in self.reach:continue
            for i,o in enumerate(b.ops):
                if o.result>=0:defs[o.result]=(b.name,i)
                for v in sources(o,self.defs):refs[v].append((b.name,i))
        # A snapshot can be consumed straight from its C memory *only* if
        # it cannot have changed between the snapshot and its LAST use.
        for v,o in self.defs.items():
            if o.code!='load' or o.args[0] in self.arrays:continue
            where=defs.get(v)
            uses=refs.get(v,[])
            if not where or any(b!=where[0] for b,_ in uses):continue
            b=next(b for b in t.blocks if b.name==where[0]); start=where[1]
            last=max((pos for _,pos in uses),default=start)
            if any(x.code in ('call','store_index') or
                   x.code=='store' and x.args[0]==o.args[0]
                   for x in b.ops[start+1:last+1]):continue
            # Compare cost of direct absolute accesses against one snapshot
            # through zero page. The latter has a store and cheaper reloads.
            n=len(uses); w=self.width(o.type)
            snap=5*w+2*w*n
            direct=3*w*n
            if direct<=snap:
                self.direct.add(v)
                self.decisions['direct_load']+=1
        # Fused operation+sink recipe. Never fuse a value used elsewhere.
        for b in t.blocks:
            if b.name not in self.reach:continue
            for i,o in enumerate(b.ops):
                if o.code!='store':continue
                dst,v=o.args
                if refs.get(v)!=[(b.name,i)]:continue
                parent=self.defs[v]
                if parent.code not in ('+','-','&','|','^'):continue
                if defs[v][0]!=b.name:continue
                a,bb=parent.args
                if any(self.defs[x].code not in ('load','const') for x in (a,bb)):continue
                # Both operands must still equal their captured values.
                if any(x not in self.direct and self.defs[x].code=='load' for x in (a,bb)):continue
                if any(x.code in ('call','store_index') or
                       x.code=='store' and x.args[0] in (self.defs[a].args[0] if self.defs[a].code=='load' else None,
                                                        self.defs[bb].args[0] if self.defs[bb].code=='load' else None)
                       for x in b.ops[defs[v][1]+1:i]):continue
                self.fused[v]=(dst,parent)
                self.skip.add(v)
                self.decisions['fused_store']+=1
        # A correct fallthrough skip does not change machine state.
        self.nextblock={b.name:(t.blocks[i+1].name if i+1<len(t.blocks) else None)
                        for i,b in enumerate(t.blocks)}

    def _find_scan_plan(self,t):
        """Prove a *whole-function* byte-array sentinel scan from tape CFG.

        The recipe replaces a 16-bit integer index with a persistent pointer
        and an end pointer. It only accepts a canonical call-free CFG with no
        other writes, no aliases, one exit from the scan and a nonnegative
        signed bound. It must NEVER decide based on function/source names.
        """
        bs={b.name:b for b in t.blocks if b.name in self.reach}
        if len(bs)!=7:return None
        entry=bs.get('entry')
        if not entry or len(entry.ops)!=3:return None
        st=entry.ops[1]
        if st.code!='store' or entry.ops[0].code!='const' or entry.ops[0].args!=(0,):return None
        var=st.args[0]
        if st.args[1]!=entry.ops[0].result or entry.ops[2].code!='jump':return None
        hdr=bs.get(entry.ops[2].args[0]);
        if not hdr or len(hdr.ops)!=4:return None
        i,bound,compare,branch=hdr.ops
        if not (i.code=='load' and i.args==(var,) and bound.code=='load'
                and compare.code=='<' and compare.args==(i.result,bound.result)
                and branch.code=='branch' and branch.args[0]==compare.result):return None
        if self.t.values[i.result]!='s16' or self.t.values[bound.result]!='s16':return None
        if bound.args[0]==var:return None
        body=bs.get(branch.args[1]);end=bs.get(branch.args[2]);
        if not body or len(body.ops)!=6 or not end or len(end.ops)!=2:return None
        arr,idx,read,marker,cmpop,bt=body.ops
        if not(arr.code=='load' and arr.args[0] in self.arrays and
               self.arrays[arr.args[0]][0]=='u8' and
               idx.code=='load' and idx.args==(var,) and
               read.code=='read' and read.args==(arr.result,idx.result) and
               marker.code=='load' and cmpop.code in ('==','!=') and
               cmpop.args==(read.result,marker.result) and
               bt.code=='branch' and bt.args[0]==cmpop.result):return None
        yes=bs.get(bt.args[1]);no=bs.get(bt.args[2]);
        if not yes or len(yes.ops)!=2 or not no or len(no.ops)!=1:return None
        if yes.ops[0].code!='const' or yes.ops[1].code!='return' or yes.ops[1].args!=(yes.ops[0].result,):return None
        if no.ops[0].code!='jump':return None
        join=bs.get(no.ops[0].args[0]);
        if not join or len(join.ops)!=5:return None
        l,one,plus,store,jump=join.ops
        if not(l.code=='load' and l.args==(var,) and one.code=='const' and one.args==(1,) and
               plus.code=='+' and plus.args==(l.result,one.result) and
               store.code=='store' and store.args==(var,plus.result) and
               jump.code=='jump' and jump.args==(hdr.name,)):return None
        if not(end.ops[0].code=='const' and end.ops[1].code=='return' and
               end.ops[1].args==(end.ops[0].result,)):return None
        if self.t.types[var]!='s16':return None
        return dict(arr=arr.args[0],bound=bound.args[0],marker=marker.args[0],
                    match=cmpop.code,found=yes.ops[0].args[0],done=end.ops[0].args[0])

    def _emit_scan_plan(self,p):
        """A bounded 16-bit cursor with no general address recomputation."""
        arr,bound,marker=p['arr'],p['bound'],p['marker']
        self.mark('entry')
        # C signed i=0 < signed bound is false when bound <= 0.
        self.emit('lda',bound+'+1');self.emit('bmi','__scan_done')
        self.emit('ora',bound);self.emit('beq','__scan_done')
        # end = &array[0] + bound; carry naturally propagates.
        self.emit('clc');self.emit('lda',bound);self.emit('adc','#<'+arr);self.emit('sta','__ix')
        self.emit('lda',bound+'+1');self.emit('adc','#>'+arr);self.emit('sta','__ix+1')
        self.emit('lda','#<'+arr);self.emit('sta','__ap')
        self.emit('lda','#>'+arr);self.emit('sta','__ap+1')
        self.mark('__scan_loop')
        self.emit('lda','__ap');self.emit('cmp','__ix');self.emit('bne','__scan_read')
        self.emit('lda','__ap+1');self.emit('cmp','__ix+1');self.emit('beq','__scan_done')
        self.mark('__scan_read')
        self.emit('ldy','#$00');self.emit('lda','(__ap),y');self.emit('cmp',marker)
        self.emit('bne' if p['match']=='!=' else 'beq','__scan_found')
        self.emit('inc','__ap');self.emit('bne','__scan_loop')
        self.emit('inc','__ap+1');self.emit('jmp','__scan_loop')
        self.mark('__scan_found')
        self.emit('lda','#$%02x'%(p['found']&255))
        if self.width(self.t.rtype)==2:self.emit('ldx','#$%02x'%((p['found']>>8)&255))
        self.emit('rts')
        self.mark('__scan_done')
        self.emit('lda','#$%02x'%(p['done']&255))
        if self.width(self.t.rtype)==2:self.emit('ldx','#$%02x'%((p['done']>>8)&255))
        self.emit('rts')
        self.decisions['whole_loop_cursor']+=1

    def mark(self,label):
        # Unknown predecessor state at every CFG join; maintain simple local
        # state only. A loop planner must establish *explicit* backedge state.
        self.machine=MachineState()
        super().mark(label)

    def emit(self,op,arg=None):
        m=self.machine
        if op=='lda' and arg is not None and m.a==arg and m.flags==('nz',arg):
            self.decisions['redundant_lda_elided']+=1
            return
        super().emit(op,arg)
        if op=='lda':m.a=arg;m.flags=('nz',arg)
        elif op=='ldx':m.x=arg;m.flags=('nz_x',arg)
        elif op=='ldy':m.y=arg;m.flags=('nz_y',arg)
        elif op=='sta':
            if arg==m.a:m.a=None
            if arg in (m.x,m.y):m.x=None;m.y=None
            if arg and ('(' in str(arg) or ',y' in str(arg) or ',x' in str(arg)):
                m.a=None;m.x=None;m.y=None
        elif op in ('jsr','jmp','rts','pla','tax','tay','txa','tya','inx','iny','dex','dey'):
            # Control flow and register transfer effects need precise recipe.
            m.a=None;m.x=None;m.y=None;m.flags=None
        elif op in ('adc','sbc','and','ora','eor','asl','rol','lsr','ror','inc','dec','cmp','cpx','cpy','bit','clc','sec','bne','beq','bcs','bcc','bmi','bpl'):
            m.flags=None
            if op in ('adc','sbc','and','ora','eor','asl','rol','lsr','ror'):m.a=None

    def val(self,v,high=False):
        src=self.defs[v]
        if src.code=='neg' and self.defs[src.args[0]].code=='const':
            n=(-self.defs[src.args[0]].args[0])&65535
            return '#$%02x'%((n>>(8 if high else 0))&255)
        if v in self.direct:
            name=self.defs[v].args[0]
            if high and self.width(self.t.values[v])==1:return '#$00'
            return name+('+1' if high else '')
        return super().val(v,high)

    def compare(self,o,yes,no):
        a,b=o.args
        L,R=self.defs[a],self.defs[b]
        cond=o.code
        if L.code=='const' and R.code!='const':
            a,b=b,a;L,R=R,L
            cond={'<':'>','<=':'>=','>':'<','>=':'<=','==':'==','!=':'!='}[cond]
        # A signed 16-bit C comparison of a zero-extended byte against a
        # small positive constant is just an 8-bit 6502 compare, irrespective
        # of C's promotion rules. Preserve both carry and Z semantics.
        if self.t.values[a] in ('u8','bool') and R.code=='const' and 0<=R.args[0]<=255:
            self.emit('lda',self.val(a))
            self.emit('cmp','#$%02x'%R.args[0])
            if cond in ('==','!=','<','>='):
                self.emit({'==':'beq','!=':'bne','<':'bcc','>=':'bcs'}[cond],yes)
                self.emit('jmp',no)
            elif cond=='<=':
                self.emit('bcc',yes);self.emit('beq',yes);self.emit('jmp',no)
            elif cond=='>':
                self.emit('bcc',no);self.emit('beq',no);self.emit('jmp',yes)
            self.decisions['byte_compare']+=1
            return
        if R.code=='const' and R.args[0]==0 and cond in ('==','!='):
            self.emit('lda',self.val(a));self.emit('ora',self.val(a,True))
            self.emit('beq' if cond=='==' else 'bne',yes);self.emit('jmp',no)
            self.decisions['zero_test']+=1
            return
        return super().compare(o,yes,no)

    def op(self,o):
        c,a,k,d=o.code,o.args,o.type,o.result
        if c=='load' and d in self.direct:return
        if c=='neg' and self.defs[a[0]].code=='const':
            self.decisions['constant_negation']+=1
            return
        if c=='jump' and a[0]==self.nextblock.get(self.current_block):
            self.decisions['fallthrough_jump']+=1;return
        if c in ('+','-','&','|','^') and d in self.skip:return
        if c=='store' and a[1] in self.fused:
            dest,parent=self.fused[a[1]]
            assert dest==a[0]
            l,r=parent.args
            code={'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[parent.code]
            self.emit('lda',self.val(l))
            if parent.code in ('+','-'):self.emit('clc' if parent.code=='+' else 'sec')
            self.emit(code,self.val(r));self.emit('sta',dest)
            if self.width(self.t.types[dest])==2:
                self.emit('lda',self.val(l,True));self.emit(code,self.val(r,True));self.emit('sta',dest+'+1')
            return
        if c=='read':
            base,idx=a;b=self.defs[base]
            arr=b.args[0] if b.code=='load' and b.args[0] in self.arrays else None
            ele=self.arrays[arr][0] if arr else 'u8'
            ix=self.defs[idx]
            simple=(self.t.values[idx] in ('u8','bool') or ix.code=='const' and 0<=ix.args[0]<=255)
            if simple and ele=='u8':
                self.emit('ldy',self.val(idx))
                if arr:self.emit('lda',arr+',y')
                else:
                    self.emit('lda',self.val(base));self.emit('sta','__ap')
                    self.emit('lda',self.val(base,True));self.emit('sta','__ap+1')
                    self.emit('lda','(__ap),y')
                self.emit('sta','__v%d'%d)
                self.decisions['direct_index']+=1
                return
        return super().op(o)

    def run(self):
        if self.scan_plan:
            self._emit_scan_plan(self.scan_plan)
            return '\n'.join(self.lines)+'\n'
        # A separate, flat loop: no pre-existing optimisation inheritance.
        self.demanded_bool={o.args[1] for b in self.t.blocks for o in b.ops
            if o.code=='store' and self.defs[o.args[1]].code in ('==','!=','<','<=','>','>=')}
        self.demanded_bool|={o.args[0] for b in self.t.blocks for o in b.ops
            if o.code=='return' and self.defs[o.args[0]].code in ('==','!=','<','<=','>','>=')}
        for b in self.t.blocks:
            if b.name not in self.reach:continue
            self.current_block=b.name
            self.mark(b.name)
            for i,o in enumerate(b.ops):
                self.current_pos=i
                self.op(o)
        return '\n'.join(self.lines)+'\n'
