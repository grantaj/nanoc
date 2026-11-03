"""Real nanoc1 semantic parser -> C traversal lowerer -> 6502 interpreter.

The parser has no second C lexer/parser. The GCC oracles are extracted from the
exact original production compiler. The 6502 ABI remains experimental and its
pointer ZP homes are initialised by this test adapter, not linked startup code.
"""
import ctypes
import pathlib
import random
import re
import subprocess
import tempfile

ROOT=pathlib.Path(__file__).parent
SOURCE=(ROOT.parent/'nanoc1'/'nanoc1.c').read_text()

from test_6502 import Machine

def original_function(name):
    m=re.search(r'^char\s+'+re.escape(name)+r'\s*\([^)]*\)\s*\{',SOURCE,re.M)
    assert m,name
    d=1;p=m.end()
    while d:
        if SOURCE[p]=='{':d+=1
        if SOURCE[p]=='}':d-=1
        p+=1
    return SOURCE[m.start():p]


def declarations():
    names=('global_name','global_name_len','token_text','token_length','global_count')
    result=[]
    for name in names:
        m=re.search(r'^char\s+'+name+r'(?:\[\d+\])?\s*;',SOURCE,re.M)
        assert m,name
        result.append(m.group())
    return '\n'.join(result)+'\n'


with tempfile.TemporaryDirectory() as tmp:
    tmp=pathlib.Path(tmp)
    driver=tmp/'parser2'
    subprocess.run(['cc','-std=c99','-funsigned-char','-O0',
                    str(ROOT/'parser_tape_driver.c'),'-o',str(driver)],check=True)
    oracle=tmp/'oracle.c'
    oracle.write_text(declarations()+'\n'+original_function('same_bytes')+'\n'+original_function('find_global'))
    so=tmp/'oracle.so'
    subprocess.run(['cc','-std=c99','-funsigned-char','-O0','-shared','-fPIC',
                    str(oracle),'-o',str(so)],check=True)
    lib=ctypes.CDLL(str(so))
    cases={}
    for name in ('same_bytes','find_global'):
        source=original_function(name) if name=='same_bytes' else declarations()+original_function(name)
        p=subprocess.run([str(driver)],input=source.encode(),capture_output=True)
        if p.returncode:
            raise AssertionError((name,p.returncode,p.stderr.decode()))
        listing=p.stdout.decode()
        scalars={}
        pointers={}
        for line in p.stderr.decode().splitlines():
            parts=line.split()
            if len(parts)==3 and parts[0]=='NC2VAR':scalars[parts[1]]=int(parts[2])
            if len(parts)==3 and parts[0]=='NC2PTR':pointers[parts[1]]=int(parts[2])
        assert 'rts' in listing.lower(),name
        assert scalars and (name=='find_global' or pointers)
        cases[name]=(listing,scalars,pointers)

    def machine_for(name):
        listing,scalars,pointers=cases[name]
        m=Machine(listing)
        for k in range(1,32):m.addr[f'__v{k}']=0x30+k
        return m,scalars,pointers

    def set_pointer(m,slot,address):
        base=m.addr[f'__tptr{slot:02x}']
        m.m[base]=address&255;m.m[base+1]=address>>8

    rng=random.Random(0x6502)
    lib.same_bytes.argtypes=[ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ubyte,
                             ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ubyte]
    lib.same_bytes.restype=ctypes.c_ubyte
    for q in range(4000):
        n=rng.randrange(256);n2=n if q%9 else rng.randrange(256)
        a=bytearray(rng.randrange(256) for _ in range(256));b=bytearray(a)
        if n and q%2==0:b[rng.randrange(n)]^=1
        expected=lib.same_bytes((ctypes.c_ubyte*256).from_buffer_copy(a),n,
                                (ctypes.c_ubyte*256).from_buffer_copy(b),n2)
        m,s,p=machine_for('same_bytes')
        m.m[0x40f0:0x40f0+256]=a
        m.m[0x51e8:0x51e8+256]=b
        set_pointer(m,p['a'],0x40f0)
        set_pointer(m,p['b'],0x51e8)
        m.m[m.addr[f'__v{s["a_length"]}']]=n
        m.m[m.addr[f'__v{s["b_length"]}']]=n2
        actual,_=m.run(400000)
        assert actual==expected,('same_bytes',q,actual,expected)

    lib.find_global.argtypes=[];lib.find_global.restype=ctypes.c_ubyte
    gname=(ctypes.c_ubyte*5632).in_dll(lib,'global_name')
    glen=(ctypes.c_ubyte*176).in_dll(lib,'global_name_len')
    token=(ctypes.c_ubyte*192).in_dll(lib,'token_text')
    tokenlen=ctypes.c_ubyte.in_dll(lib,'token_length')
    gcount=ctypes.c_ubyte.in_dll(lib,'global_count')
    for q in range(2500):
        count=rng.randrange(177);name_len=rng.randrange(32)
        for j in range(count):
            glen[j]=rng.randrange(32)
            for k in range(32):gname[j*32+k]=rng.randrange(256)
        for k in range(name_len):token[k]=rng.randrange(256)
        if count and q%2==0:
            j=rng.randrange(count);glen[j]=name_len
            for k in range(name_len):gname[j*32+k]=token[k]
        tokenlen.value=name_len;gcount.value=count
        expected=lib.find_global()
        m,s,p=machine_for('find_global')
        m.m[m.addr['global_name_len']:m.addr['global_name_len']+176]=bytes(glen)
        m.m[m.addr['global_name']:m.addr['global_name']+5632]=bytes(gname)
        m.m[m.addr['token_text']:m.addr['token_text']+192]=bytes(token)
        m.m[m.addr[f'__v{s["token_length"]}']]=name_len
        m.m[m.addr[f'__v{s["global_count"]}']]=count
        actual,_=m.run(400000)
        assert actual==expected,('find_global',q,actual,expected)

        # Unsupported but valid C must not be silently lowered to byte code.
    extra = [
        original_function('same_bytes').replace('i = i + 1;', 'i = i + 2;'),
        original_function('same_bytes').replace('char same_bytes(', 'int same_bytes('),
    ]
    for source in extra:
        p=subprocess.run([str(driver)],input=source.encode(),capture_output=True)
        assert p.returncode!=0, ('unsupported code accepted',p.stdout.decode())
    print('Original semantic parser -> C traversal lowerer -> 6502: 6500/6500 oracle comparisons; word and recurrence guards passed')
