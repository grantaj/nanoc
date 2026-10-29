"""Experimental typed operation tape from an actual C function (pycparser parsing).
Not production nanoc and no source-name-specific machine rules.
"""
from dataclasses import dataclass,field
from pycparser import c_parser,c_ast
import ast

@dataclass
class Op:
    code:str
    args:tuple
    type:str=''
    result:int=-1

@dataclass
class Block:
    name:str
    ops:list=field(default_factory=list)

class TapeBuilder:
    def __init__(self,source):
        tree=c_parser.CParser().parse(source)
        self.fns={x.decl.name:x for x in tree.ext if isinstance(x,c_ast.FuncDef)}
        if len(self.fns)!=1:raise ValueError('one function')
        self.fn=next(iter(self.fns.values()))
        self.types={};self.arrays={};self.calls={};self.call_params={}
        for x in tree.ext:
            if not isinstance(x,c_ast.Decl):continue
            if isinstance(x.type,c_ast.FuncDecl):
                self.calls[x.name]=self.dtype(x.type.type)
                self.call_params[x.name]=[self.dtype(p.type) for p in (x.type.args.params if x.type.args else [])]
            else:
                self.types[x.name]=self.dtype(x.type)
                if isinstance(x.type,c_ast.ArrayDecl):
                    self.arrays[x.name]=self.dtype(x.type.type)
        for p in (self.fn.decl.type.args.params if self.fn.decl.type.args else []):
            self.types[p.name]=self.dtype(p.type)
        self.rtype=self.dtype(self.fn.decl.type.type)
        self.strings={};self.blocks=[];self.pos=None;self.seq=0;self.nextvalue=0;self.values={};self.live=True;self.breaks=[]
        self.block('entry')
    def dtype(self,t):
        if isinstance(t,c_ast.PtrDecl):return 'ptr'
        if isinstance(t,c_ast.ArrayDecl):return 'array'
        if isinstance(t,c_ast.TypeDecl):
            names=t.type.names
            if names==['char']:return 'u8'
            if names==['int']:return 's16'
            if names==['unsigned']:return 'u16'
        raise TypeError(t)
    def label(self,p):self.seq+=1;return f'{p}_{self.seq}'
    def block(self,name):
        b=Block(name);self.blocks.append(b);self.pos=b;self.live=True
        return b
    def emit(self,code,*args,kind='',res=False):
        val=self.nextvalue if res else -1
        if res:self.values[val]=kind;self.nextvalue+=1
        self.pos.ops.append(Op(code,args,kind,val));return val
    def end(self,code,*args):
        if not self.live:raise ValueError('double terminal '+self.pos.name)
        self.emit(code,*args);self.live=False
    def const(self,n,typ='s16'):return self.emit('const',n,kind=typ,res=True)
    def load(self,n):return self.emit('load',n,kind=self.types[n],res=True)
    def promote(self,k):return 's16' if k in ('u8','bool') else k
    def arith_type(self,a,b):
        t1=self.promote(self.values[a]);t2=self.promote(self.values[b]);return 'u16' if 'u16' in (t1,t2) else 's16'
    def expr(self,node):
        if isinstance(node,c_ast.ID):return self.load(node.name)
        if isinstance(node,c_ast.Constant):
            if node.type=='char':return self.const(ord(ast.literal_eval(node.value)))
            if node.type=='string':
                name='__text_'+str(len(self.strings))
                self.strings[name]=ast.literal_eval(node.value).encode('latin1')+b'\x00'
                return self.emit('string',name,kind='ptr',res=True)
            if node.type=='int':
                n=int(node.value,0);return self.const(n,'u16' if n>32767 else 's16')
            raise ValueError(('constant',node.type))
        if isinstance(node,c_ast.ArrayRef):
            ptr=self.expr(node.name);idx=self.expr(node.subscript)
            if isinstance(node.name,c_ast.ID):
                name=node.name.name
                kind=self.arrays.get(name,'u8')
                if kind=='ptr':kind='u8'
            else:kind='u8'
            return self.emit('read',ptr,idx,kind=kind,res=True)
        if isinstance(node,c_ast.FuncCall):
            args=[self.expr(a) for a in node.args.exprs] if node.args else []
            name=node.name.name
            return self.emit('call',name,*args,kind=self.calls[name],res=True)
        if isinstance(node,c_ast.UnaryOp):
            v=self.expr(node.expr)
            if node.op=='-':return self.emit('neg',v,kind='s16',res=True)
            if node.op=='!':return self.emit('not',v,kind='bool',res=True)
            raise NotImplementedError('unary '+node.op)
        if isinstance(node,c_ast.BinaryOp):
            if node.op in ('&&','||'):
                raise NotImplementedError('short-circuit control flow not lowered')
            a=self.expr(node.left);b=self.expr(node.right)
            k='bool' if node.op in ('==','!=','<','<=','>','>=') else self.arith_type(a,b)
            return self.emit(node.op,a,b,kind=k,res=True)
        raise NotImplementedError('expr '+type(node).__name__)
    def stmt(self,node):
        if node is None or not self.live:return
        if isinstance(node,c_ast.Compound):
            for x in node.block_items or []:self.stmt(x)
        elif isinstance(node,c_ast.Decl):
            self.types[node.name]=self.dtype(node.type)
            if node.init is not None:self.emit('store',node.name,self.expr(node.init))
        elif isinstance(node,c_ast.Assignment):
            if node.op!='=':raise NotImplementedError('assignment operator')
            if isinstance(node.lvalue,c_ast.ID):self.emit('store',node.lvalue.name,self.expr(node.rvalue))
            elif isinstance(node.lvalue,c_ast.ArrayRef):
                base=self.expr(node.lvalue.name);ix=self.expr(node.lvalue.subscript);val=self.expr(node.rvalue)
                self.emit('store_index',base,ix,val)
            else:raise NotImplementedError('assignment lvalue '+type(node.lvalue).__name__)
        elif isinstance(node,c_ast.FuncCall):self.expr(node)
        elif isinstance(node,c_ast.Return):self.end('return',self.expr(node.expr))
        elif isinstance(node,c_ast.Break):
            if not self.breaks:raise ValueError('break outside loop')
            self.end('jump',self.breaks[-1])
        elif isinstance(node,c_ast.If):
            cond=self.expr(node.cond);yes=self.label('yes');no=self.label('no');done=self.label('join')
            self.end('branch',cond,yes,no)
            self.block(yes);self.stmt(node.iftrue)
            active_yes=self.live
            if active_yes:self.end('jump',done)
            self.block(no);self.stmt(node.iffalse)
            active_no=self.live
            if active_no:self.end('jump',done)
            if active_yes or active_no:self.block(done)
        elif isinstance(node,c_ast.While):
            hdr=self.label('while');body=self.label('body');done=self.label('after')
            self.end('jump',hdr)
            self.block(hdr);cond=self.expr(node.cond);self.end('branch',cond,body,done)
            self.block(body);self.breaks.append(done);self.stmt(node.stmt);self.breaks.pop()
            if self.live:self.end('jump',hdr)
            self.block(done)
        else:raise NotImplementedError('statement '+type(node).__name__)
    def build(self):
        self.stmt(self.fn.body)
        if self.live:
            # Only a syntactically proven endless final loop can leave an
            # artificial CFG after-block with no possible predecessor.
            # A dummy return terminates that *unreachable* block; never
            # invent semantics for a genuinely reachable falling off end.
            body=self.fn.body.block_items or []
            last=body[-1] if body else None
            def contains_break(node):
                if isinstance(node,c_ast.Break):return True
                return any(contains_break(child) for _,child in node.children())
            if (not isinstance(last,c_ast.While) or
                not isinstance(last.cond,c_ast.Constant) or
                last.cond.type!='int' or int(last.cond.value,0)!=1 or
                contains_break(last.stmt)):
                raise ValueError('function has fallthrough')
            self.end('return',self.const(0))
        return self

if __name__=='__main__':
    from collections import Counter
    from pathlib import Path
    t=TapeBuilder(Path(__file__).with_name('parse_atom.c').read_text()).build()
    print(len(t.blocks),'blocks',sum(len(b.ops) for b in t.blocks),'operations',t.nextvalue,'values')
    print(Counter(o.code for b in t.blocks for o in b.ops))
    for b in t.blocks:print(b.name,len(b.ops),b.ops[-1].code)
