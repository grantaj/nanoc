"""Explicit typed C argument and return ABI generation contracts.

These tests inspect the generic generator at the ABI boundary. The linked
whole-program corpus additionally executes and compares against host C.
"""
from tape_frontend import TapeBuilder
from address_plan import AddressPlanBackend

def emit(src):
    t=TapeBuilder(src).build()
    return AddressPlanBackend(t,{}).run()

code=emit('int callee(int a,char b);int f(char x,int y){return callee(x,y);}')
assert 'sta __call_callee_0\n' in code and 'sta __call_callee_0+1\n' in code
assert 'lda #$00\n    sta __call_callee_0+1' in code  # byte -> word zero-extends
assert 'sta __call_callee_1\n' in code
assert 'sta __call_callee_1+1' not in code            # word -> byte truncates
code=emit('char callee(char x);int f(char y){return callee(y);}')
assert 'sta __v' in code and 'ldx #$00\n    rts' in code # caller promotes byte to word
code=emit('int callee(int x);char f(char y){return callee(y);}')
assert 'stx __v' in code and 'ldx #$00\n    rts' not in code # caller truncates word
code=emit('char callee(char x);char f(char y){return callee(y);}')
assert 'jsr callee\n    rts' in code # return forwarding when types agree
print('PASS four generic signed/byte argument and return-ABI contracts')
