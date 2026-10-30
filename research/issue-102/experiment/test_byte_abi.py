"""Verify byte-return A-only ABI and signed-word callers at all 256 inputs."""
from machine_verify import Machine,SYM
from test_indexed_abi import call,mnew

n=0
for i in range(256):
    m=mnew()
    m.X=0xa5
    m.write(SYM['__L_upper_char_c'],i)
    a,x,steps=call(m,'upper_char')
    expected=i-32 if 97<=i<=122 else i
    assert a==expected,(i,a,expected)
    n+=1
for i in range(256):
    m=mnew()
    m.X=0xa5
    m.write(SYM['__L_hex_nibble_c'],i)
    a,x,steps=call(m,'hex_nibble')
    c=i-32 if 97<=i<=122 else i
    v=(c-48 if 48<=c<=57 else c-65+10 if 65<=c<=70 else -1)&65535
    assert a|(x<<8)==v,(i,a,x,v)
    n+=1
print(f'PASS {n} exhaustive 8-bit return + 16-bit-promoted caller cases')
