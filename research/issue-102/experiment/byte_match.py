"""Byte-for-byte verify physically linked code with real bootstrap/ass.c.
The host-compiled *exact* original ass.c generates reference bytes for every
function and runtime segment, with external symbol addresses fixed to the
physical linked image.  This is stronger than a research encoder size match.
"""
from pathlib import Path
from pycparser import c_parser,c_ast
import re,json,ctypes
R=Path(__file__).parent;S=R/'full_corpus'
source=re.sub(r'/\*.*?\*/','',(S/'ass.c').read_text(),flags=re.S)
functions=[x.decl.name for x in c_parser.CParser().parse(source).ext if isinstance(x,c_ast.FuncDef)]
lines=(R/'compact_image.asm').read_text().splitlines()
symbols=json.loads((R/'compact_resolved.json').read_text())
binary=(R/'compact_image.prg').read_bytes()[2:]
lib=ctypes.CDLL(str(S/'host_ass.so'))
lib.ass_assemble.argtypes=[ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_char_p,ctypes.c_ubyte,ctypes.c_uint]
lib.ass_assemble.restype=ctypes.c_ubyte

def assemble_segment(start_symbol,end_symbol):
 start=next(i for i,x in enumerate(lines) if x==start_symbol+':')
 stop=next(i for i,x in enumerate(lines) if x==end_symbol+':')
 chunk=lines[start:stop]
 own={x[:-1] for x in chunk if x.endswith(':')} | {x.split('=',1)[0].strip() for x in chunk if re.fullmatch(r'\S+\s*=\s*\S+',x.strip())}
 used=set()
 for x in chunk:
  s=x.strip().split(';')[0]
  if not s or s.endswith(':') or s.startswith('byte '):continue
  _,_,a=s.partition(' ')
  a=a.strip().lstrip('#').lstrip('<>').replace('(','').replace(')','')
  a=re.sub(r',[xy]$','',a)
  m=re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)(?:\+\d+)?',a)
  if m and m.group(1) not in own:used.add(m.group(1))
 def val(k):
  v=symbols[k]
  if isinstance(v,str):v=symbols[v]
  return v
 defs='\n'.join('%s = $%04x'%(name,val(name)) for name in sorted(used))
 text='* = $%04x\n'%symbols[start_symbol]+defs+'\n'+'\n'.join(chunk)+'\n'
 path=R/'strict_files'/(start_symbol+'.physical.asm');path.write_text(text)
 p=str(path).encode();ret=lib.ass_assemble(p,len(p),b'',0,symbols[start_symbol])
 n=ctypes.c_int.in_dll(lib,'ass_image_length').value
 oracle=bytes((ctypes.c_ubyte*11264).in_dll(lib,'ass_image'))[:n]
 expected=binary[symbols[start_symbol]-0x0800:symbols[end_symbol]-0x0800]
 match=ret==0 and oracle==expected
 print(f'{start_symbol:34s} bytes={n:5d} expected={len(expected):5d} result={ret} match={match}',flush=True)
 if not match:
  for i,(a,b) in enumerate(zip(oracle,expected)):
   if a!=b:
    print('first mismatch at',i,'got',hex(a),'expected',hex(b));break
  print('head',oracle[:30].hex(), expected[:30].hex())
 return match

checks=[assemble_segment(functions[i],functions[i+1]) for i in range(len(functions)-1)]
checks.append(assemble_segment(functions[-1],'__nc_init'))
checks.append(assemble_segment('__nc_init','__experiment_entry'))
# Startup+embedded filename until BSS-only definitions: synthetic end marker
# inserted as data-zero boundary from symbol table instead.
print('REAL ASS.C byte-for-byte matched:',sum(checks),'/',len(checks))
(R/'byte_match_result.json').write_text(json.dumps({'segments':len(checks),'matched':sum(checks),'passed':all(checks)},indent=2))
assert all(checks)
