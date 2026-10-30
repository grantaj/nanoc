"""Conventional 6502 widening of the simple AST emitter.

No virtual registers/optimiser. A = low byte, X = high byte at expression,
call and return boundaries. A is also the byte expression result. Y = byte
address offset; __ap = scratch zero-page pointer. This class deliberately
rejects operations that require unproved alias/call or signedness reasoning.
"""
import ast
from pycparser import c_parser,c_ast
from natural6502 import Natural6502,Unsupported

class Natural6502Wide(Natural6502):
    def __init__(self,source,arrays=None):
        unit=c_parser.CParser().parse(source)
        fs=[n for n in unit.ext if isinstance(n,c_ast.FuncDef)]
        if len(fs)!=1:raise Unsupported('expected exactly one function')
        self.fn=fs[0];self.name=self.fn.decl.name;self.arrays=arrays or {}
        self.types={};self.calls={};self.params={};self.lines=[];self.label_index=0
        for node in unit.ext:
            if not isinstance(node,c_ast.Decl):continue
            if isinstance(node.type,c_ast.FuncDecl):
                self.calls[node.name]=self.kind(node.type.type)
                self.params[node.name]=[self.kind(p.type) for p in (node.type.args.params if node.type.args else [])]
            else:self.types[node.name]=self.kind(node.type)
        ps=self.fn.decl.type.args.params if self.fn.decl.type.args else []
        for p in ps:self.types[p.name]=self.kind(p.type)
        self.ret=self.kind(self.fn.decl.type.type)
        if self.ret not in ('u8','s16','u16'):raise Unsupported('return type')
        self.loop_index=None;self.pointers={}
        self.scope={p.name for p in ps};self.islocal=set(self.scope)
        self.stmt(self.fn.body)

    def kexpr(self,n):
        if isinstance(n,c_ast.ID):return self.types[n.name]
        if isinstance(n,c_ast.Constant):return 's16' if n.type=='int' else 'u8'
        if isinstance(n,c_ast.UnaryOp):return 's16'
        if isinstance(n,c_ast.ArrayRef):
            if isinstance(n.name,c_ast.ID):
                base=n.name.name
                return self.arrays.get(base,('u8',0))[0] if self.types.get(base)=='array' else 'u8'
            return 'unknown'
        if isinstance(n,c_ast.BinaryOp):
            ka,kb=self.kexpr(n.left),self.kexpr(n.right)
            return 'u16' if ('u16' in (ka,kb) or 'ptr' in (ka,kb)) else 's16'
        if isinstance(n,c_ast.FuncCall):return self.calls[n.name.name]
        if isinstance(n,c_ast.Cast):return self.kind(n.to_type.type)
        return 'unknown'

    def direct16(self,node,high=False):
        if isinstance(node,c_ast.ID):
            kind=self.types[node.name]
            return (self.loc(node.name)+'+1' if high else self.loc(node.name)) if kind in ('s16','u16','ptr') else '#$00' if high and kind=='u8' else self.loc(node.name) if kind=='u8' else self.fail('operand type')
        if isinstance(node,c_ast.Constant):
            n=self.number(node)&0xffff
            return '#$%02x'%((n>>8 if high else n)&255)
        if isinstance(node,c_ast.UnaryOp) and node.op=='-' and isinstance(node.expr,c_ast.Constant):
            n=(-self.number(node.expr))&65535
            return '#$%02x'%((n>>8 if high else n)&255)
        raise Unsupported('not a direct 16-bit operand')
    def fail(self,reason):raise Unsupported(reason)

    def array_element_kind(self,n):
        if not isinstance(n,c_ast.ArrayRef) or not isinstance(n.name,c_ast.ID):raise Unsupported('array reference')
        base=n.name.name
        if self.types.get(base)=='ptr':return 'u8'
        if self.types.get(base)=='array':return self.arrays.get(base,('u8',0))[0]
        raise Unsupported('not array or pointer')

    def address_of(self,n):
        """Produce effective address in __ap, with no fake 16-bit indexes.

        The fast path is direct Y for byte offsets. The wide path explicitly
        scales a word index and adds a two-byte base; it never silently wraps Y.
        """
        if not isinstance(n,c_ast.ArrayRef) or not isinstance(n.name,c_ast.ID):raise Unsupported('address')
        base=n.name.name
        kind=self.array_element_kind(n)
        index=n.subscript
        if self.effects_call(index):raise Unsupported('call in index')
        self.eval16(index)
        self.emit('sta','__tmp0');self.emit('stx','__tmp1')
        if kind!='u8':
            self.emit('asl','__tmp0');self.emit('rol','__tmp1')
        if self.types.get(base)=='ptr':
            lo,hi=self.loc(base),self.loc(base)+'+1'
        else:
            lo,hi='#<'+base,'#>'+base
        self.emit('clc');self.emit('lda',lo);self.emit('adc','__tmp0');self.emit('sta','__ap')
        self.emit('lda',hi);self.emit('adc','__tmp1');self.emit('sta','__ap+1')

    def array_get(self,n,wide=False):
        self.address_of(n)
        self.emit('ldy','#$00');self.emit('lda','(__ap),y')
        if wide:
            self.emit('sta','__tmp0')
            self.emit('iny');self.emit('lda','(__ap),y');self.emit('tax')
            self.emit('lda','__tmp0')

    def array_put(self,n,value):
        kind=self.array_element_kind(n)
        if self.effects_call(n.subscript):raise Unsupported('call in store index')
        if kind=='u8':
            self.eval(value);self.emit('sta','__tmp2')
        else:
            self.eval16(value);self.emit('sta','__tmp2');self.emit('stx','__tmp3')
        self.address_of(n)
        self.emit('ldy','#$00');self.emit('lda','__tmp2');self.emit('sta','(__ap),y')
        if kind!='u8':
            self.emit('iny');self.emit('lda','__tmp3');self.emit('sta','(__ap),y')

    def eval16(self,n):
        """Produce A low and X high. No intermediate results in named homes."""
        if isinstance(n,(c_ast.ID,c_ast.Constant)) or (isinstance(n,c_ast.UnaryOp) and n.op=='-' and isinstance(n.expr,c_ast.Constant)):
            self.emit('lda',self.direct16(n));self.emit('ldx',self.direct16(n,True));return
        if isinstance(n,c_ast.Cast):
            self.eval16(n.expr);return
        if isinstance(n,c_ast.ArrayRef):
            if self.array_element_kind(n)!='u8':
                self.array_get(n,True)
            else:
                self.eval(n)
                self.emit('ldx','#$00')
            return
        if isinstance(n,c_ast.BinaryOp) and n.op in ('+','-','&','|','^'):
            # A,X from left; right is direct byte/word operand. This is one
            # normal 6502 low-then-high operation, with one byte of scratch.
            lo,hi=self.direct16(n.right),self.direct16(n.right,True)
            # Natural low/high-byte arithmetic: when the left-hand word is
            # addressable, don't materialise either input into scratch.
            try:
                lhs_lo=self.direct16(n.left)
                lhs_hi=self.direct16(n.left,True)
            except Unsupported:
                lhs_lo=lhs_hi=None
            if lhs_lo is not None:
                self.emit('lda',lhs_lo)
            else:
                self.eval16(n.left)
                self.emit('sta','__tmp0')
                self.emit('txa');self.emit('sta','__tmp1')
                self.emit('lda','__tmp0')
            if n.op in ('+','-'):self.emit('clc' if n.op=='+' else 'sec')
            self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[n.op],lo)
            self.emit('sta','__tmp0')
            self.emit('lda',lhs_hi if lhs_hi is not None else '__tmp1')
            self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[n.op],hi)
            self.emit('tax');self.emit('lda','__tmp0');return
        if isinstance(n,c_ast.FuncCall):
            self.emit_call(n)
            if self.kexpr(n)=='u8':self.emit('ldx','#$00')
            return
        raise Unsupported('16-bit expression '+type(n).__name__)

    def eval_call(self,n):
        if not isinstance(n.name,c_ast.ID):raise Unsupported('indirect call')
        fn=n.name.name
        if fn not in self.calls:raise Unsupported('unknown call')
        actual=n.args.exprs if n.args else []
        kinds=self.params[fn]
        if len(actual)!=len(kinds):raise Unsupported('call arity')
        # Source-to-target parameter copies. A/X ABI and static param slots.
        # An individual arg may contain a call only if no previous argument
        # needs scratch to survive that call; static argument slots are stable.
        for j,(arg,k) in enumerate(zip(actual,kinds)):
            if k=='u8':
                self.eval(arg)
                self.emit('sta',f'__call_{fn}_{j}')
            elif k in ('u16','s16','ptr'):
                self.eval16(arg)
                self.emit('sta',f'__call_{fn}_{j}')
                self.emit('stx',f'__call_{fn}_{j}+1')
            else:raise Unsupported('parameter kind '+k)
        self.emit('jsr',fn)
    def emit_call(self,n):self.eval_call(n)

    def eval(self,n):
        # Native high-byte extraction from a 16-bit word, not a shift loop.
        if isinstance(n,c_ast.BinaryOp) and n.op=='&' and isinstance(n.right,c_ast.Constant):
            mask=self.number(n.right)
            if mask==65535:
                if self.kexpr(n.left)=='u8':return super().eval(n.left)
                self.eval16(n.left);return
            if mask==255:
                if isinstance(n.left,c_ast.BinaryOp) and n.left.op=='>>' and isinstance(n.left.right,c_ast.Constant) and self.number(n.left.right)==8:
                    self.emit('lda',self.direct16(n.left.left,True));return
                if self.kexpr(n.left) in ('s16','u16','ptr'):
                    self.emit('lda',self.direct16(n.left));return
        if isinstance(n,c_ast.BinaryOp) and n.op=='>>' and isinstance(n.right,c_ast.Constant) and self.number(n.right)==8:
            self.emit('lda',self.direct16(n.left,True));return
        if isinstance(n,c_ast.FuncCall):
            self.eval_call(n);return
        if isinstance(n,c_ast.ArrayRef) and isinstance(n.name,c_ast.ID):
            if self.array_element_kind(n)!='u8':raise Unsupported('word array loaded as byte')
            name=n.name.name
            if (self.types.get(name)=='ptr' and isinstance(n.subscript,c_ast.Constant)
                    and 0<=self.number(n.subscript)<=255):
                self.emit('lda',self.loc(name));self.emit('sta','__ap')
                self.emit('lda',self.loc(name)+'+1');self.emit('sta','__ap+1')
                self.emit('ldy','#$%02x'%self.number(n.subscript))
                self.emit('lda','(__ap),y');return
            if self.kexpr(n.subscript) in ('s16','u16'):
                self.array_get(n);return
        return super().eval(n)

    def save16(self,name):
        self.emit('sta',self.loc(name));self.emit('stx',self.loc(name)+'+1')

    def test_false(self,n,fail):
        if isinstance(n,c_ast.BinaryOp) and n.op in ('==','!=','<','<=','>','>='):
            kleft,kright=self.kexpr(n.left),self.kexpr(n.right)
            if kleft in ('s16','u16','ptr') or kright in ('s16','u16','ptr'):
                # Signedness must be known before selecting comparisons.
                # Handle simple constant zero tests and direct word compares.
                signed=(kleft=='s16' and kright in ('s16','u8')) or (kright=='s16' and kleft in ('s16','u8'))
                if isinstance(n.right,c_ast.Constant) and self.number(n.right)==0:
                    if n.op in ('==','!='):
                        self.emit('lda',self.direct16(n.left));self.emit('ora',self.direct16(n.left,True))
                        self.emit('bne' if n.op=='==' else 'beq',fail)
                        return
                    if n.op in ('<','>=') and signed:
                        self.emit('lda',self.direct16(n.left,True))
                        self.emit('bpl' if n.op=='<' else 'bmi',fail)
                        return
                # Compare high bytes first, then low bytes; signed high is
                # normalised with EOR #$80 for unsigned CMP ordering.
                self.word_compare_false(n,fail,signed)
                return
        return super().test_false(n,fail)

    def word_compare_false(self,n,fail,signed):
        """Compare words with normal 6502 high/low branches.

        Cost is paid only for the paths that require a low-byte comparison.
        No boolean construction, no four-way jump diamond.
        """
        if self.effects_call(n):raise Unsupported('comparison call effects')
        # Two arbitrary pure C operands may include wide array reads.
        # Give them independent short-lived machine homes; no location may
        # alias scratch used by the address constructor.
        try:
            a0,a1=self.direct16(n.left),self.direct16(n.left,True)
        except Unsupported:
            self.eval16(n.left)
            self.emit('sta','__tmp4');self.emit('stx','__tmp5')
            a0,a1='__tmp4','__tmp5'
        try:
            b0,b1=self.direct16(n.right),self.direct16(n.right,True)
        except Unsupported:
            self.eval16(n.right)
            self.emit('sta','__tmp6');self.emit('stx','__tmp7')
            b0,b1='__tmp6','__tmp7'
        if signed:
            # Signed order is unsigned order after flipping the high sign bit.
            # Fold the transform into immediates where possible.
            if a1.startswith('#$'):
                a1='#$%02x'%(int(a1[2:],16)^0x80)
            else:
                self.emit('lda',a1);self.emit('eor','#$80');self.emit('sta','__tmp0');a1='__tmp0'
            if b1.startswith('#$'):
                b1='#$%02x'%(int(b1[2:],16)^0x80)
            else:
                self.emit('lda',b1);self.emit('eor','#$80');self.emit('sta','__tmp1');b1='__tmp1'
        op=n.op
        if op in ('==','!='):
            self.emit('lda',a1);self.emit('cmp',b1)
            if op=='==':
                self.emit('bne',fail)
                self.emit('lda',a0);self.emit('cmp',b0);self.emit('bne',fail)
            else:
                done=self.label();self.emit('bne',done)
                self.emit('lda',a0);self.emit('cmp',b0);self.emit('beq',fail)
                self.mark(done)
            return
        done=self.label()
        self.emit('lda',a1);self.emit('cmp',b1)
        if op in ('<','<='):
            self.emit('bcc',done);self.emit('bne',fail)
        else:
            self.emit('bcc',fail);self.emit('bne',done)
        self.emit('lda',a0);self.emit('cmp',b0)
        if op=='<':self.emit('bcs',fail)
        elif op=='>=':self.emit('bcc',fail)
        elif op=='>':self.emit('beq',fail);self.emit('bcc',fail)
        elif op=='<=':self.emit('beq',done);self.emit('bcs',fail)
        else:raise Unsupported('word comparison '+op)
        self.mark(done)

    def stmt(self,n):
        if isinstance(n,c_ast.While):
            header,done=self.label(),self.label()
            self.mark(header);self.test_false(n.cond,done)
            old=getattr(self,'loop_exit',None)
            self.loop_exit=done
            try:self.stmt(n.stmt)
            finally:self.loop_exit=old
            self.emit('jmp',header);self.mark(done);return
        if isinstance(n,c_ast.Break):
            if getattr(self,'loop_exit',None) is None:raise Unsupported('break outside while')
            self.emit('jmp',self.loop_exit);return
        if isinstance(n,c_ast.Assignment) and n.op=='=' and isinstance(n.lvalue,c_ast.ArrayRef):
            self.array_put(n.lvalue,n.rvalue);return
        if isinstance(n,c_ast.Decl) and self.kind(n.type) in ('s16','u16','ptr'):
            self.types[n.name]=self.kind(n.type);self.islocal.add(n.name)
            if n.init:self.eval16(n.init);self.save16(n.name)
            return
        if isinstance(n,c_ast.Assignment) and n.op=='=' and isinstance(n.lvalue,c_ast.ID):
            name=n.lvalue.name
            if self.types.get(name) in ('s16','u16','ptr'):
                value=n.rvalue
                if (isinstance(value,c_ast.BinaryOp) and value.op in ('+','-') and isinstance(value.left,c_ast.ID)
                        and value.left.name==name and isinstance(value.right,c_ast.Constant) and self.number(value.right)==1):
                    lo,hi=self.loc(name),self.loc(name)+'+1'
                    skip=self.label()
                    if value.op=='+':
                        self.emit('inc',lo);self.emit('bne',skip);self.emit('inc',hi)
                    else:
                        self.emit('lda',lo);self.emit('bne',skip);self.emit('dec',hi);self.mark(skip);self.emit('dec',lo)
                        return
                    self.mark(skip);return
                self.eval16(value);self.save16(name);return
        if isinstance(n,c_ast.Return):
            if self.ret in ('s16','u16'):
                self.eval16(n.expr);self.emit('rts');return
            self.eval(n.expr);self.emit('rts');return
        return super().stmt(n)
