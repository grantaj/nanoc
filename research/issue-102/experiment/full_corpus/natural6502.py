"""Small, deliberately conventional MOS 6502 source-level code generator.

Experimental independent C AST emitter. Not a general compiler, not a peephole
optimizer, and no function-specific patterns. A evaluates byte expressions,
flags express comparisons, Y indexes bytes, and ZP __ap holds a pointer for
(zp),Y. Unsupported C uses the validated reference generator instead.

This first experiment deliberately uses a simple static ABI and handles only
byte-returning functions whose computations are provably byte sized.
"""
from pycparser import c_parser, c_ast
import ast

class Unsupported(Exception): pass

class Natural6502:
    def __init__(self, source, arrays=None):
        unit=c_parser.CParser().parse(source)
        fs=[x for x in unit.ext if isinstance(x,c_ast.FuncDef)]
        if len(fs)!=1:raise Unsupported('expected exactly one C function')
        self.fn=fs[0]; self.name=self.fn.decl.name
        self.arrays=arrays or {}
        self.types={};self.calls={}; self.params={};self.lines=[];self.label_index=0
        for node in unit.ext:
            if not isinstance(node,c_ast.Decl):continue
            if isinstance(node.type,c_ast.FuncDecl):
                self.calls[node.name]=self.kind(node.type.type)
                self.params[node.name]=[self.kind(x.type) for x in (node.type.args.params if node.type.args else [])]
            else:self.types[node.name]=self.kind(node.type)
        for node in (self.fn.decl.type.args.params if self.fn.decl.type.args else []):
            self.types[node.name]=self.kind(node.type)
        self.ret=self.kind(self.fn.decl.type.type)
        if self.ret!='u8':raise Unsupported('return must be char')
        self.loop_index=None;self.pointers={}
        self.scope={p.name for p in (self.fn.decl.type.args.params if self.fn.decl.type.args else [])}
        self.islocal=set(self.scope)
        self.stmt(self.fn.body)

    def kind(self, type_):
        if isinstance(type_,c_ast.ArrayDecl):return 'array'
        if isinstance(type_,c_ast.PtrDecl):return 'ptr'
        if isinstance(type_,c_ast.TypeDecl):
            names=type_.type.names
            return 'u8' if names==['char'] else 's16' if names==['int'] else 'u16' if names==['unsigned'] else 'unknown'
        return 'unknown'
    def label(self):
        self.label_index+=1
        return '__nat%d'%self.label_index
    def loc(self,name):
        return '__L_%s_%s'%(self.name,name) if name in self.islocal else name
    def emit(self,op,arg=None):
        self.lines.append('    '+op+(' '+arg if arg is not None else ''))
    def mark(self,label):self.lines.append(label+':')
    def number(self,node):
        if not isinstance(node,c_ast.Constant):raise Unsupported('not a literal')
        if node.type=='int':return int(node.value,0)
        if node.type=='char':return ord(ast.literal_eval(node.value))
        raise Unsupported('literal kind')
    def byte_operand(self,node):
        if isinstance(node,c_ast.Constant):
            x=self.number(node)
            if not 0<=x<=255:raise Unsupported('not byte constant')
            return '#$%02x'%x
        if (isinstance(node,c_ast.ArrayRef) and self.loop_index is not None
            and isinstance(node.name,c_ast.ID) and isinstance(node.subscript,c_ast.ID)
            and node.subscript.name==self.loop_index and node.name.name in self.pointers):
            return '('+self.pointers[node.name.name]+'),y'
        if isinstance(node,c_ast.ID) and self.types[node.name]=='u8':
            return self.loc(node.name)
        raise Unsupported('not direct byte operand')
    def eval(self,node):
        # Result in A, no register allocation or materialised expression values.
        if isinstance(node,(c_ast.ID,c_ast.Constant)):
            self.emit('lda',self.byte_operand(node));return
        if isinstance(node,c_ast.BinaryOp) and node.op in ('+','-','&','|','^'):
            right=self.byte_operand(node.right)
            self.eval(node.left)
            if node.op in ('+','-'):self.emit('clc' if node.op=='+' else 'sec')
            self.emit({'+':'adc','-':'sbc','&':'and','|':'ora','^':'eor'}[node.op],right)
            return
        if isinstance(node,c_ast.ArrayRef):
            if not isinstance(node.name,c_ast.ID):raise Unsupported('array base expression')
            base=node.name.name
            if self.types[base] not in ('array','ptr'):raise Unsupported('array base type')
            if (self.loop_index and isinstance(node.subscript,c_ast.ID)
                and node.subscript.name==self.loop_index):
                if base in self.pointers:
                    self.emit('lda','('+self.pointers[base]+'),y');return
                if self.types[base]=='array':
                    self.emit('lda',base+',y');return
                raise Unsupported('loop pointer was not prepared')
            index=self.byte_operand(node.subscript)
            self.emit('ldy',index)
            if self.types[base]=='array':
                if self.arrays.get(base,('u8',0))[0]!='u8':raise Unsupported('word array')
                self.emit('lda',base+',y')
            else:
                self.emit('lda',self.loc(base));self.emit('sta','__ap')
                self.emit('lda',self.loc(base)+'+1');self.emit('sta','__ap+1')
                self.emit('lda','(__ap),y')
            return
        if isinstance(node,c_ast.FuncCall):
            if not isinstance(node.name,c_ast.ID):raise Unsupported('indirect call')
            fn=node.name.name
            actual=node.args.exprs if node.args else []
            if self.calls.get(fn)!='u8' or any(x!='u8' for x in self.params[fn]):
                raise Unsupported('nonbyte call ABI')
            if len(actual)!=len(self.params[fn]):raise Unsupported('call arity')
            for j,x in enumerate(actual):
                self.eval(x);self.emit('sta',f'__call_{fn}_{j}')
            self.emit('jsr',fn);return
        raise Unsupported('expression '+type(node).__name__)
    def effects_call(self,node):
        if isinstance(node,c_ast.FuncCall):return True
        return any(self.effects_call(c) for _,c in node.children())
    def test_false(self,node,fail):
        """Emit a short conditional branch to failure, success falls through.

        This is the default 6502 control idiom, not later CFG repair.
        """
        if isinstance(node,c_ast.BinaryOp) and node.op in ('==','!=','<','<=','>','>='):
            # Compare byte-valued operands only. C integer promotions remain
            # semantically valid because both original values are in 0..255.
            if self.effects_call(node):raise Unsupported('comparison with call')
            for x in (node.left,node.right):
                if isinstance(x,c_ast.BinaryOp):raise Unsupported('word arithmetic condition')
            try:right=self.byte_operand(node.right)
            except Unsupported:right=None
            if right is not None:
                self.eval(node.left);self.emit('cmp',right)
            else:
                self.eval(node.left);self.emit('sta','__tmp0')
                self.eval(node.right);self.emit('sta','__tmp1')
                self.emit('lda','__tmp0');self.emit('cmp','__tmp1')
            if node.op in ('==','!=','<','>='):
                self.emit({'==':'bne','!=':'beq','<':'bcs','>=':'bcc'}[node.op],fail)
            elif node.op=='>':
                self.emit('beq',fail);self.emit('bcc',fail)
            elif node.op=='<=':
                ok=self.label();self.emit('beq',ok);self.emit('bcs',fail);self.mark(ok)
            return
        self.eval(node);self.emit('beq',fail)
    def try_byte_cursor_loop(self,init,loop,remaining):
        # Ordinary Y = unit byte index convention. This is a *proof* of the
        # program's simple loop contract, not an exact-source/fn recognizer.
        if self.loop_index is not None:return False
        if not isinstance(init,c_ast.Assignment) or init.op!='=' or not isinstance(init.lvalue,c_ast.ID):return False
        iv=init.lvalue.name
        if self.types.get(iv)!='u8' or iv not in self.islocal:return False
        if not isinstance(init.rvalue,c_ast.Constant) or self.number(init.rvalue)!=0:return False
        if not isinstance(loop,c_ast.While) or not isinstance(loop.cond,c_ast.BinaryOp):return False
        cond=loop.cond
        if (cond.op!='<' or not isinstance(cond.left,c_ast.ID) or cond.left.name!=iv
            or not isinstance(cond.right,(c_ast.ID,c_ast.Constant))):return False
        if isinstance(cond.right,c_ast.ID) and self.types.get(cond.right.name)!='u8':return False
        if isinstance(cond.right,c_ast.Constant) and not 0<=self.number(cond.right)<=255:return False
        stmts=loop.stmt.block_items if isinstance(loop.stmt,c_ast.Compound) else [loop.stmt]
        if not stmts or self.effects_call(loop.stmt):return False
        last=stmts[-1]
        if not isinstance(last,c_ast.Assignment) or last.op!='=' or not isinstance(last.lvalue,c_ast.ID) or last.lvalue.name!=iv:return False
        plus=last.rvalue
        if not isinstance(plus,c_ast.BinaryOp) or plus.op!='+' or not isinstance(plus.left,c_ast.ID) or plus.left.name!=iv:return False
        if not isinstance(plus.right,c_ast.Constant) or self.number(plus.right)!=1:return False
        # Do not remove an observable C local or change an otherwise escaping
        # pointer's state. Only whole-index loops whose value dies on exit.
        def reads(n):
            if isinstance(n,c_ast.ID):return n.name==iv
            return any(reads(c) for _,c in n.children())
        if any(reads(n) for n in remaining):return False
        bases=set()
        def inspect(n):
            if isinstance(n,c_ast.ArrayRef):
                if not (isinstance(n.name,c_ast.ID) and isinstance(n.subscript,c_ast.ID) and n.subscript.name==iv):raise Unsupported('mixed byte indexes')
                if self.types.get(n.name.name) not in ('ptr','array'):raise Unsupported('bad array type')
                bases.add(n.name.name)
            if isinstance(n,c_ast.Assignment) and isinstance(n.lvalue,c_ast.ID):
                if n.lvalue.name!=iv or n is not last:raise Unsupported('loop mutates state')
            for _,c in n.children():inspect(c)
        try:inspect(loop.stmt)
        except Unsupported:return False
        ptrs=[x for x in sorted(bases) if self.types[x]=='ptr']
        if len(ptrs)>2:return False
        # The body must not contain an expression that requires another use
        # of Y or a clobbering function call. The supported AST operations
        # can be validated by compiling a candidate transactionally.
        old_lines=self.lines[:];old_index=self.loop_index;old_ptrs=self.pointers.copy()
        try:
            self.loop_index=iv
            self.pointers={base:('__ap' if k==0 else '__ix') for k,base in enumerate(ptrs)}
            for base,zp in self.pointers.items():
                self.emit('lda',self.loc(base));self.emit('sta',zp)
                self.emit('lda',self.loc(base)+'+1');self.emit('sta',zp+'+1')
            self.emit('ldy','#$00')
            header,done=self.label(),self.label()
            self.mark(header)
            self.emit('cpy',self.byte_operand(cond.right));self.emit('bcs',done)
            for stmt in stmts[:-1]:self.stmt(stmt)
            self.emit('iny');self.emit('jmp',header)
            self.mark(done)
        except Unsupported:
            self.lines=old_lines;self.loop_index=old_index;self.pointers=old_ptrs
            return False
        self.loop_index=old_index;self.pointers=old_ptrs
        return True

    def stmt(self,node):
        if node is None:return
        if isinstance(node,c_ast.Compound):
            seq=node.block_items or []
            j=0
            while j<len(seq):
                if (j+1<len(seq) and self.try_byte_cursor_loop(seq[j],seq[j+1],seq[j+2:])):
                    j+=2
                else:self.stmt(seq[j]);j+=1
            return
        if isinstance(node,c_ast.Decl):
            if self.kind(node.type)!='u8':raise Unsupported('local type '+node.name)
            self.types[node.name]='u8';self.islocal.add(node.name)
            if node.init:
                self.eval(node.init);self.emit('sta',self.loc(node.name))
            return
        if isinstance(node,c_ast.Assignment):
            if node.op!='=' or not isinstance(node.lvalue,c_ast.ID):raise Unsupported('assignment lvalue')
            name=node.lvalue.name
            if self.types[name]!='u8':raise Unsupported('assignment type')
            # The usual direct 6502 increment/decrement is a primitive,
            # not an instruction-rewrite pass.
            value=node.rvalue
            if (isinstance(value,c_ast.BinaryOp) and isinstance(value.left,c_ast.ID)
                    and value.left.name==name and isinstance(value.right,c_ast.Constant)
                    and self.number(value.right)==1 and value.op in ('+','-')):
                self.emit('inc' if value.op=='+' else 'dec',self.loc(name));return
            self.eval(value);self.emit('sta',self.loc(name));return
        if isinstance(node,c_ast.Return):
            self.eval(node.expr);self.emit('rts');return
        if isinstance(node,c_ast.If):
            fail=self.label()
            self.test_false(node.cond,fail)
            self.stmt(node.iftrue)
            if node.iffalse is None:
                self.mark(fail)
            else:
                end=self.label();self.emit('jmp',end)
                self.mark(fail);self.stmt(node.iffalse);self.mark(end)
            return
        if isinstance(node,c_ast.While):
            header,done=self.label(),self.label()
            self.mark(header);self.test_false(node.cond,done)
            self.stmt(node.stmt);self.emit('jmp',header)
            self.mark(done)
            return
        if isinstance(node,c_ast.FuncCall):self.eval(node);return
        raise Unsupported('statement '+type(node).__name__)
    def run(self):return 'entry:\n'+'\n'.join(self.lines)+'\n'
