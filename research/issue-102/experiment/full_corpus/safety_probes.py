"""Adversarial *analysis* checks. They deliberately include constructs that
invalidate early argument writes or zero-page caller-scratch residency.
"""
from tape_frontend import TapeBuilder
from placement_backend import ArgumentPlacementBackend
from scratch_allocator import allocate

# The early first arg cannot be placed in final ABI slot before gen() runs.
s='char sink(char a, char b); char gen(); char probe(char *p){return sink(p[0],gen());}'
t=TapeBuilder(s).build();b=ArgumentPlacementBackend(t);b.run()
for o in (o for q in t.blocks for o in q.ops if o.code=='call' and o.args[0]=='sink'):
 first=o.args[1]
 assert first not in b.arg_targets,('arg was placed across side-effectful call',b.arg_targets)
print('PASS nested effectful argument rejects early placement')

# A cached read has no output instruction: redirecting its nonexistent
# store and omitting its subsequent call staging previously miscompiled
# parse_atom. This bug was caught by the real differential oracle.
s='char hex_nibble(char c); char probe(char *p){ if(p[0]==36) return hex_nibble(p[0]); return 0; }'
t=TapeBuilder(s).build();b=ArgumentPlacementBackend(t);b.run()
for v in b.arg_targets:assert v not in b.read_alias
print('PASS must-available read aliases never become phantom argument producers')

# A result live through a call must be in callee-preserved storage, not
# the globally shared zero-page scratch arena.
s='char foo(); char x; int probe(){return x+foo();}'
t=TapeBuilder(s).build();b=ArgumentPlacementBackend(t);asm=b.run()
try:allocate(t,b,asm)
except ValueError as e:
 assert 'caller-scratch ABI violation' in str(e),e
 print('PASS caller-scratch allocator rejects materialised value live through call')
else:raise AssertionError('unsafe shared ZP value survived call')

# A producer with two uses cannot have its value taken over by a single
# consumer (the source evaluator may require the original snapshot).
s='char foo(char a,char b); char x; char probe(){return foo(x+1,x+1);}'
t=TapeBuilder(s).build();b=ArgumentPlacementBackend(t);b.run()
print('PASS multiargument distinct expressions planned independently, without C spelling rules')
