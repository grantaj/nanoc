"""Full capacity + overflow boundary test of pointer-cursor source variant."""
import ctypes,sys,json,os
from pathlib import Path
ROOT=Path(os.environ.get('SEMANTIC_CASE_ROOT',Path(__file__).resolve().parent))
results=[]
for dirname in ('nanoc_machine_value_home_planner','cursor_variant'):
    lib=ctypes.CDLL(str(ROOT/dirname/'full_corpus/host_ass.so'))
    lib.reset_assembler.argtypes=[ctypes.c_ushort,ctypes.c_char_p,ctypes.c_ubyte]
    lib.reset_assembler.restype=ctypes.c_ubyte
    lib.stage_byte.argtypes=[ctypes.c_ubyte]
    lib.stage_byte.restype=ctypes.c_ubyte
    state=lib.reset_assembler(0,b'',0)
    statuses=[]
    for i in range(11264):
        s=lib.stage_byte((i*17+29)&255)
        if s!=0:raise AssertionError((dirname,i,s))
    overflow=lib.stage_byte(0xab)
    length=ctypes.c_int.in_dll(lib,'ass_image_length').value
    b=bytes((ctypes.c_ubyte*11264).in_dll(lib,'ass_image'))
    want=bytes((i*17+29)&255 for i in range(11264))
    assert b==want,(dirname,'bytes')
    assert length==11264,(dirname,length)
    assert overflow!=0,(dirname,overflow)
    results.append({'variant':dirname,'reset_status':state,'length':length,'overflow_status':overflow,'output_matches':True})
assert results[0]['overflow_status']==results[1]['overflow_status']
print(json.dumps({'byte_stages_per_version':11264,'results':results},indent=2))
