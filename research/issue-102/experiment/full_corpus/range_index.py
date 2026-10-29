"""Conservative CFG-edge interval proof for direct-Y indexed access.

Only a proved 0..255 *value at the indexed consumer* can bypass 16-bit
address construction. Follows C's unsigned-byte / signed-word semantics;
truncating a signed/unsigned word index on its type alone is never allowed.
This is research-only, across the existing typed tape, not source patterns.
"""
from collections import deque,defaultdict
from compare_native import NativeCompareBackend

CMPS={'==','!=','<','<=','>','>='}
SWAP={'<':'>','<=':'>=','>':'<','>=':'<=','==':'==','!=':'!='}
NEGATE={'<':'>=','<=':'>','>':'<=','>=':'<','==':'!=','!=':'=='}

class IndexRangeBackend(NativeCompareBackend):
    def __init__(self,t,arrays=None,**kwargs):
        super().__init__(t,arrays,**kwargs)
        self.proven_y=set()
        self.range_evidence=[]
        self.prove_y_consumers()
        self.narrow_proved_index_arithmetic()

    @staticmethod
    def bounds(t):
        return {'u8':(0,255),'bool':(0,1),'s16':(-32768,32767),
                'u16':(0,65535),'ptr':(0,65535),'array':(0,65535)}.get(t,(-32768,32767))

    def interval(self,v, vals, env):
        d=self.defs[v]
        if v in vals:return vals[v]
        if d.code=='const':
            x=d.args[0]&65535
            if self.t.values[v]=='s16' and x>=32768:x-=65536
            return (x,x)
        # Loads from *another* block have a snapshot lifetime which we cannot
        # associate with the current environment. Only the block simulator's
        # already-saved vals may convey a narrowed interval.
        if d.code=='load':return self.bounds(d.type)
        if d.code in ('identity','low8','high8'):
            if d.code=='identity':return self.interval(d.args[0],vals,env)
            return (0,255)
        return self.bounds(self.t.values[v])

    def arithmetic(self,o,vals,env):
        a=o.args
        bound=self.bounds(o.type)
        if o.code=='load':return env.get(o.args[0],bound)
        if o.code in ('const','identity','low8','high8'):
            return self.interval(o.result,vals,env)
        if o.code in ('+','-'):
            x=self.interval(a[0],vals,env);y=self.interval(a[1],vals,env)
            lo,hi=((x[0]+y[0],x[1]+y[1]) if o.code=='+' else
                   (x[0]-y[1],x[1]-y[0]))
            # No modular-wrap assumption. A width overflow loses precision.
            return (lo,hi) if bound[0]<=lo<=hi<=bound[1] else bound
        if o.code in CMPS or o.code=='not':return (0,1)
        if o.code=='neg':
            x=self.interval(a[0],vals,env)
            lo,hi=-x[1],-x[0]
            return (lo,hi) if bound[0]<=lo<=hi<=bound[1] else bound
        return bound

    def default_state(self):
        return {x:self.bounds(t) for x,t in self.t.types.items()}

    def narrow_branch(self,compare,yes,env,vals,load_ops_since_effect):
        if compare.code not in CMPS:return env
        a,b=compare.args;da,db=self.defs[a],self.defs[b]
        if da.code=='const' and db.code=='load':
            a,b=b,a;da,db=db,da;op=SWAP[compare.code]
        elif da.code=='load' and db.code=='const':op=compare.code
        else:return env
        name=da.args[0]
        # The comparison has to refer to the current scalar value; no effect
        # may have invalidated its load within this basic block.
        if a not in load_ops_since_effect:return env
        n=self.interval(b,vals,env)
        if n[0]!=n[1]:return env
        c=n[0];op=op if yes else NEGATE[op]
        lo,hi=env[name]
        if op=='<':hi=min(hi,c-1)
        elif op=='<=':hi=min(hi,c)
        elif op=='>':lo=max(lo,c+1)
        elif op=='>=':lo=max(lo,c)
        elif op=='==':lo=max(lo,c);hi=min(hi,c)
        # != cannot in general represent a hole in an interval.
        if lo>hi:return None
        result=dict(env);result[name]=(lo,hi)
        return result

    def simulate_block(self,b,entry,collect=False):
        env=dict(entry);vals={};fresh_loads=set();hits=[]
        for o in b.ops:
            c=o.code
            if o.result>=0:
                vals[o.result]=self.arithmetic(o,vals,env)
            if c in ('read','store_index'):
                idx=o.args[1]
                r=self.interval(idx,vals,env)
                # Never infer from raw type alone: this is the interval for
                # the exact indexed expression at this consumer.
                if 0<=r[0]<=r[1]<=255:
                    base=self.defs[o.args[0]]
                    arr=base.args[0] if base.code=='load' and base.args[0] in self.arrays else None
                    element=self.arrays[arr][0] if arr else 'u8'
                    if element=='u8' and collect:
                        hits.append((id(o),b.name,idx,r,c))
            if c=='load':fresh_loads.add(o.result)
            if c=='store':
                name,v=o.args
                value=self.interval(v,vals,env)
                typ=self.t.types[name];lo,hi=self.bounds(typ)
                # C char assignment truncates modulo 256; retain precision
                # only when the source is already representable.
                env[name]=value if lo<=value[0]<=value[1]<=hi else (lo,hi)
                fresh_loads={v for v in fresh_loads if self.defs[v].args[0]!=name}
            if c=='call':
                # With no address-of locals in this Phase-1 frontend, calls
                # may modify globals, but cannot write caller scalar params
                # or locals by alias. The globals are from declarations outside
                # the function body; we infer them from the parsed C function.
                for name in self.global_names:env[name]=self.bounds(self.t.types[name])
                fresh_loads={v for v in fresh_loads if self.defs[v].args[0] not in self.global_names}
            if c=='store_index':
                # No address-of scalars is expressible in this frontend;
                # indirect writes may alias global arrays, not local scalars.
                for name in self.global_names:env[name]=self.bounds(self.t.types[name])
                fresh_loads={v for v in fresh_loads if self.defs[v].args[0] not in self.global_names}
        term=b.ops[-1]
        if term.code=='branch':
            comp=self.defs[term.args[0]]
            return [(term.args[1],self.narrow_branch(comp,True,env,vals,fresh_loads)),
                    (term.args[2],self.narrow_branch(comp,False,env,vals,fresh_loads))], hits
        if term.code=='jump':return [(term.args[0],env)],hits
        return [],hits

    def prove_y_consumers(self):
        # Only scalar parameters/locals cannot be reached through arbitrary
        # call/indirect-write effects in the supported frontend (no &).
        from pycparser import c_ast
        class LocalVisitor(c_ast.NodeVisitor):
            def __init__(self):self.names=set()
            def visit_Decl(self,n):
                if not isinstance(n.type,c_ast.FuncDecl):self.names.add(n.name)
        visit=LocalVisitor();visit.visit(self.t.fn.body)
        params=self.t.fn.decl.type.args.params if self.t.fn.decl.type.args else []
        local=visit.names|{p.name for p in params}
        self.global_names=set(self.t.types)-local-set(self.arrays)
        blocks={b.name:b for b in self.t.blocks if b.name in self.reach}
        states={'entry':self.default_state()};q=deque(['entry']);iterations=defaultdict(int)
        while q:
            name=q.popleft();iterations[name]+=1
            edges,_=self.simulate_block(blocks[name],states[name])
            for dest,new in edges:
                if new is None or dest not in blocks:continue
                old=states.get(dest)
                if old is None:
                    states[dest]=new;q.append(dest);continue
                joined={v:(min(old[v][0],new[v][0]),max(old[v][1],new[v][1])) for v in old}
                if iterations[dest]>16:
                    # Widen loop-changing facts to top: slow convergence may
                    # cost optimisation but must never produce a false proof.
                    joined={v:(self.bounds(self.t.types[v]) if joined[v]!=old[v] else old[v]) for v in old}
                if joined!=old:states[dest]=joined;q.append(dest)
        for name,state in states.items():
            _,hits=self.simulate_block(blocks[name],state,True)
            self.range_evidence.extend(hits)
            self.proven_y.update(hit[0] for hit in hits)

    def narrow_proved_index_arithmetic(self):
        # Only a word +/- whose *only* consumer is the certified indexed
        # access may discard its unobservable high-byte work. The consumer
        # is allowed to use Y precisely because the full C word is 0..255
        # at that CFG point. Other consumers retain the original width.
        from collections import Counter
        uses=Counter()
        for b in self.t.blocks:
            for o in b.ops:
                for v in self.uses(o):
                    if isinstance(v,int) and v in self.defs:uses[v]+=1
        self.narrowed_index_arith=set()
        for b in self.t.blocks:
            for o in b.ops:
                if id(o) not in self.proven_y:continue
                idx=o.args[1];d=self.defs[idx]
                if (uses[idx]==1 and d.code in ('+','-') and
                    self.t.values[idx] in ('s16','u16') and
                    getattr(self,'width_needs',{}).get(idx,2)==2):
                    self.width_needs[idx]=1
                    self.narrowed_index_arith.add(idx)

    def y_safe(self,o):
        return id(o) in getattr(self,'proven_y',())
