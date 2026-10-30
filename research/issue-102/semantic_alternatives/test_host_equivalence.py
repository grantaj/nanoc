"""Compare original and cursor-source host C byte-for-byte on all 29 cases."""
from pathlib import Path
import ctypes,sys,tempfile
base,variant=map(Path,sys.argv[1:])
sys.path.insert(0,str(base))
source=(base/'machine_cases.py').read_text().split('counts=[];started=time.time()')[0]
namespace={'__file__':str(base/'machine_cases.py')}
exec(source,namespace)
libs=[ctypes.CDLL(str(p/'full_corpus'/'host_ass.so')) for p in (base,variant)]
for lib in libs:
 lib.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
 lib.ass_assemble.restype=ctypes.c_ubyte
with tempfile.TemporaryDirectory() as td:
 filename=Path(td)/'T.ASM'
 for name,src in namespace['programs'].items():
  filename.write_bytes(src)
  outputs=[]
  for lib in libs:
   status=lib.ass_assemble(str(filename).encode(),len(str(filename)),b'',0,0)
   length=ctypes.c_int.in_dll(lib,'ass_image_length').value
   data=bytes((ctypes.c_ubyte*11264).in_dll(lib,'ass_image'))[:length]
   outputs.append((status,data))
  assert outputs[0]==outputs[1],name
print('EXACT HOST SOURCE EQUIVALENCE',len(namespace['programs']),'/',len(namespace['programs']))
