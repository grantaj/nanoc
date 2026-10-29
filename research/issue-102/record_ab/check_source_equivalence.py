#!/usr/bin/env python3
"""Run 29 existing programs plus five larger cases through two *host-C* oracles.

Usage: python check_source_equivalence.py BASELINE_WORKDIR RECORD_WORKDIR
Both directories must contain a compiled full_corpus/host_ass.so and original
machine_cases.py; run reproduce_ab.sh first.

This is a source-algorithm differential control, not 6502 interpreter coverage.
"""
import ctypes
import sys
import tempfile
from pathlib import Path

base, variant = map(Path, sys.argv[1:3])
filename=base/'machine_cases.py'
# The program corpus definitions occur before the test runner. Don't execute
# the original runner or import its binary-specific emulator.
fragment=filename.read_text().split('counts=[];started=time.time()')[0]
fragment=fragment.replace('from machine_verify import Machine,SYM,run_oracle\n','')
env={'__file__':str(filename),'__name__':'source_equivalence_fixture'}
exec(compile(fragment,str(filename),'exec'),env)
programs=env['programs']

n=850
programs['stress_850_symbols']=('\n'.join(['* = $0800']+[f's{i:03d} = ${i*13%65536:04x}' for i in range(n)]+[f'word s{i:03d}' for i in range(n-1,-1,-1)])+'\n').encode()
programs['stress_590_byte_fixups']=('\n'.join(['* = $0800'] + ['byte <futurelabel']*590 + ['futurelabel: rts'])+'\n').encode()
programs['stress_645_fixup_overflow']=('\n'.join(['* = $0800'] + ['byte <futurelabel']*645 + ['futurelabel: rts'])+'\n').encode()
programs['stress_symbol_capacity']=('\n'.join(['* = $0800']+[f's{i:03d} = ${i:04x}' for i in range(905)])+'\n').encode()
programs['stress_local_scopes']=('\n'.join(['* = $0800']+[f'global_{i:03d}: .local: byte 1' for i in range(100)])+'\n').encode()

libs=[ctypes.CDLL(str(d.resolve()/'full_corpus'/'host_ass.so')) for d in [base,variant]]
for lib in libs:
    lib.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
    lib.ass_assemble.restype=ctypes.c_ubyte

for i,(name,data) in enumerate(programs.items(),1):
    with tempfile.TemporaryDirectory(prefix='nanoc_source_ab_') as temp:
        p=Path(temp)/'test.asm';p.write_bytes(data)
        results=[]
        for lib in libs:
            status=lib.ass_assemble(str(p).encode(),len(str(p)),b'',0,0)
            size=ctypes.c_int.in_dll(lib,'ass_image_length').value
            data=bytes((ctypes.c_ubyte*11264).in_dll(lib,'ass_image'))[:size]
            results.append((status,data))
    ok=results[0]==results[1]
    print(f'{i:02}/{len(programs)} {name:28s} {"PASS" if ok else "FAIL"} '+str([int(x[0]) for x in results]),flush=True)
    if not ok:raise AssertionError(name)
print(f'SOURCE A/B PASS {len(programs)}/{len(programs)}',flush=True)
