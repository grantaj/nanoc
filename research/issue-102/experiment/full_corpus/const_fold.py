"""Generic exact 16-bit constant arithmetic on the value tape.
No source names; results are reduced modulo 2^16, Nano C's target width.
"""
from tape_frontend import Op
from dual_pointer import DualPointerBackend

def fold_constants(t):
    defs={o.result:o for b in t.blocks for o in b.ops if o.result>=0}
    count=0
    for b in t.blocks:
        for i,o in enumerate(b.ops):
            if o.result<0:continue
            if o.code=='neg':
                a=defs[o.args[0]]
                if a.code!='const':continue
                value=(-a.args[0])&65535
            elif o.code in ('+','-','*','&','|','^','<<'):
                a,v=(defs[x] for x in o.args)
                if a.code!='const' or v.code!='const':continue
                left=a.args[0]&65535;right=v.args[0]&65535
                value={'+':lambda:left+right,'-':lambda:left-right,'*':lambda:left*right,
                       '&':lambda:left&right,'|':lambda:left|right,'^':lambda:left^right,
                       '<<':lambda:(left<<right) if right<16 else 0}[o.code]()&65535
            else:continue
            new=Op('const',(value,),o.type,o.result)
            b.ops[i]=new;defs[o.result]=new;count+=1
    return count

class FoldedBackend(DualPointerBackend):
    def __init__(self,t,arrays=None,**kwargs):
        self.constant_folds=fold_constants(t)
        super().__init__(t,arrays,**kwargs)
