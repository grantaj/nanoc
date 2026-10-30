"""Checks that immediate operands derive from whole-program C facts, never guesses."""
from pycparser import c_parser
from simple6502_constants import immutable_scalars,apply_constants
from tape_frontend import TapeBuilder

def unit(s):return c_parser.CParser().parse(s)
def tape(s):return TapeBuilder(s).build()
def codes(t):return [(o.code,o.args) for b in t.blocks for o in b.ops]

s='char KEEP=4; char CHANGE=5; char fn(char x){ CHANGE=x; return KEEP+CHANGE; }'
constants=immutable_scalars(unit(s))
assert constants=={'KEEP':4}, constants
t=tape(s);assert apply_constants(t,constants)==1
assert ('const',(4,)) in codes(t)
assert ('load',('CHANGE',)) in codes(t)

s='char STATUS=6; char fn(char STATUS){return STATUS;}'
constants=immutable_scalars(unit(s))
assert constants=={'STATUS':6}
t=tape(s);assert apply_constants(t,constants)==0
assert ('load',('STATUS',)) in codes(t)

s='char STATUS=6; char fn(char x){char STATUS; STATUS=x;return STATUS;}'
constants=immutable_scalars(unit(s))
assert constants=={} # conservatively refuses a shadowed name with an assignment
t=tape(s);assert apply_constants(t,constants)==0
assert ('load',('STATUS',)) in codes(t)

s='char C=8; char *PTR; char fn(){PTR=&C;return C;}'
assert immutable_scalars(unit(s))=={}, immutable_scalars(unit(s))

s='char C=8; char fn(){C=9;return C;}'
assert immutable_scalars(unit(s))=={}, immutable_scalars(unit(s))

s='int WORD=65535; char fn(){return WORD==65535;}'
assert immutable_scalars(unit(s))=={'WORD':65535}

print('PASS six whole-unit immutability, shadowing and address-escape controls')
