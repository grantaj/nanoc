"""Machine-first Phase-1 rule: an immutable scalar is an immediate operand.

This does not search or rewrite assembly. It proves whole-unit, non-address-taken,
never-written scalar initialisers and preserves that fact as a tape constant
before 6502 selection. All other objects retain ordinary loads.
"""
from pycparser import c_ast
from tape_frontend import Op

class Writes(c_ast.NodeVisitor):
    def __init__(self):
        self.writes = set()
        self.address_taken = set()
    def visit_Assignment(self, node):
        if isinstance(node.lvalue, c_ast.ID):
            self.writes.add(node.lvalue.name)
        self.generic_visit(node)
    def visit_UnaryOp(self,node):
        if node.op in ('p++','p--','++','--') and isinstance(node.expr,c_ast.ID):
            self.writes.add(node.expr.name)
        if node.op == '&' and isinstance(node.expr,c_ast.ID):
            self.address_taken.add(node.expr.name)
        self.generic_visit(node)

def immutable_scalars(unit):
    probe=Writes()
    for f in unit.ext:
        if isinstance(f,c_ast.FuncDef):probe.visit(f)
    result={}
    for d in unit.ext:
        if not isinstance(d,c_ast.Decl) or d.init is None or not isinstance(d.type,c_ast.TypeDecl):continue
        if d.name in probe.writes or d.name in probe.address_taken:continue
        if not isinstance(d.init,c_ast.Constant) or d.init.type!='int':continue
        typ=d.type.type.names
        if typ==['char']:width=8
        elif typ in (['int'],['unsigned']):width=16
        else:continue
        result[d.name]=int(d.init.value,0)&((1<<width)-1)
    return result

def apply_constants(t,constants):
    # A local or parameter may shadow a global. Never fold the local name.
    class LocalNames(c_ast.NodeVisitor):
        def __init__(self):self.names=set()
        def visit_Decl(self,d):
            if not isinstance(d.type,c_ast.FuncDecl):self.names.add(d.name)
            self.generic_visit(d)
    scope=LocalNames()
    scope.visit(t.fn)
    count=0
    for b in t.blocks:
        for i,o in enumerate(b.ops):
            if o.code=='load' and o.args[0] in constants and o.args[0] not in scope.names:
                # This is a semantic constant result, but retains the original
                # C value kind for byte promotion and word comparisons.
                b.ops[i]=Op('const',(constants[o.args[0]],),o.type,o.result)
                count+=1
    return count
