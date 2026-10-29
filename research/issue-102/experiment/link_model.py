"""Research-only *physical* C64 layout of exact full ass.c typed-tape output.
Not a production assembler; validates constraints and emits one symbolic image.
"""
from pathlib import Path
from collections import OrderedDict
import re, json, csv, ast, sys
from pycparser import c_parser,c_ast
P=Path(__file__).parent
S=P/'full_corpus'
src=re.sub(r'/\*.*?\*/','',(S/'ass.c').read_text(),flags=re.S)
unit=c_parser.CParser().parse(src)
globals=[n for n in unit.ext if isinstance(n,c_ast.Decl) and not isinstance(n.type,c_ast.FuncDecl)]
funcs=[n for n in unit.ext if isinstance(n,c_ast.FuncDef)]
# Half-open layout. $ce00.. is runtime private and not usable for variables.
BSS_BASE=0x4800;BSS_LIMIT=0xce00
# Non-BASIC target owns BASIC work ZP; this is a candidate map, not yet
# validated for KERNAL/IRQ calls. Values live through function calls are
# rejected by the existing liveness allocation proof.
ZP={'__ap':0x02,'__ix':0x04,'__rh':0x06,'__mw':0x07}
ZP.update({f'__tmp{i}':0x09+i for i in range(8)})
ZP['NC_TMP']=0xfc;ZP['NC_PTR']=0xfe

def ty(t):
 if isinstance(t,c_ast.ArrayDecl):return ty(t.type)
 if isinstance(t,c_ast.PtrDecl):return 'ptr'
 if isinstance(t,c_ast.TypeDecl):return 'u8' if t.type.names==['char'] else 'u16' if t.type.names==['unsigned'] else 's16'
 raise ValueError(t)
def size(t):
 if isinstance(t,c_ast.ArrayDecl):return int(t.dim.value,0)*size(t.type)
 return 1 if ty(t)=='u8' else 2

def constval(n):
 if isinstance(n,c_ast.Constant):
  if n.type=='int':return int(n.value,0)
  if n.type=='char':return ord(ast.literal_eval(n.value))
  if n.type=='string':return ast.literal_eval(n.value).encode('latin1')+b'\x00'
 if isinstance(n,c_ast.UnaryOp) and n.op=='-':return -constval(n.expr)
 raise TypeError(n)
def initializer(d):
 t=d.type;total=size(t)
 def pieces(node,typ):
  if isinstance(node,c_ast.InitList):return b''.join(pieces(v,typ.type if isinstance(typ,c_ast.ArrayDecl) else typ) for v in node.exprs)
  v=constval(node)
  if isinstance(v,bytes):return v
  return int(v&((1<<(size(typ)*8))-1)).to_bytes(size(typ),'little')
 val=pieces(d.init,t)
 if len(val)>total:raise ValueError(f'initializer overflow {d.name} {len(val)}>{total}')
 return val+bytes(total-len(val))

symbols={};initialized={};bss_next=BSS_BASE
for d in globals:
 if d.init is not None:initialized[d.name]=initializer(d)
 else:
  symbols[d.name]=bss_next
  bss_next+=size(d.type)

# Every function's locals/parameters own nonrecursive static storage, like
# the existing compiler. This is intentionally conservative about recursion.
local_storage=OrderedDict();params={}
class Locals(c_ast.NodeVisitor):
 def __init__(self):self.d=[]
 def visit_Decl(self,n):
  if not isinstance(n.type,c_ast.FuncDecl):self.d.append(n)
for f in funcs:
 name=f.decl.name
 p=f.decl.type.args.params if f.decl.type.args else []
 params[name]=[x.name for x in p]
 v=Locals();v.visit(f.body)
 for d in list(p)+v.d:
  n=f'__L_{name}_{d.name}'
  if n in symbols:raise ValueError('duplicate local '+n)
  symbols[n]=bss_next
  local_storage[n]=size(d.type)
  bss_next+=size(d.type)

# The real IO target's static ABI, as defined in nanoc1/target/runtime.asm.
# Other calls alias callee's own nonrecursive static parameter slots.
extern={'io_open':('open',[0xcf10,0xcf12]),'io_read':('read',[0xcf14]),'io_close':('close',[0xcf1e])}
for name,p in params.items():
 for i,n in enumerate(p):symbols[f'__call_{name}_{i}']=symbols[f'__L_{name}_{n}']
for name,(part,locs) in extern.items():
 for i,x in enumerate(locs):symbols[f'__call_{name}_{i}']=x
ZP_PLUS={'__ap':2,'__ix':2,'__rh':1,'__mw':2,**{f'__tmp{i}':1 for i in range(8)}}
if bss_next>BSS_LIMIT:raise ValueError(f'BSS overflow: {bss_next:04x} > {BSS_LIMIT:04x}')
# ABI-safe scratch overlap across calls is checked separately per function
# using scratch_allocator.allocate.  We do not rely on scratch as persistent
# storage for locals, parameters, or globals.

# Reconstruct per-function namespaced output from per-function packed backend.
from pycparser import c_ast
from tape_frontend import TapeBuilder
from direct_address import DirectAddressBackend
from register_first import RegisterFirstBackend
from compare_native import NativeCompareBackend
from inplace_update import InplaceUpdateBackend
from pointer_home import PointerHomeBackend
import os
from scratch_allocator import allocate
from execute6502 import relax
arrays=json.loads((S/'whole_corpus'/'arrays.json').read_text())
assembly=[];size_records=[];global_tempmax=0
for f in funcs:
 name=f.decl.name
 t=TapeBuilder((S/'whole_corpus'/(name+'.c')).read_text()).build()
 b=(InplaceUpdateBackend if os.environ.get("NATIVE_INPLACE") else PointerHomeBackend if os.environ.get("POINTER_HOME") else NativeCompareBackend if os.environ.get("NATIVE_COMPARE") else RegisterFirstBackend if os.environ.get("REG_FIRST") else DirectAddressBackend)(t,arrays)
 raw=b.run();packed,info=allocate(t,b,raw)
 global_tempmax=max(global_tempmax,info['packed_bytes'])
 if info['packed_bytes']>8:raise AssertionError('ZP scratch overflow '+name)
 entries={z[:-1] for z in packed.splitlines() if z.endswith(':')}
 locs={x for x in symbols if x.startswith(f'__L_{name}_')}
 mapping={x:'__F_'+name+'_'+x for x in entries}
 mapping.update({x:'__L_'+name+'_'+x for x in (n[len('__L_'+name+'_'):] for n in locs)})
 # Function symbols are unprefixed; *internal* labels must be unique.
 strs={x:'__S_'+name+'_'+x for x in t.strings}
 mapping.update(strs)
 def renames(m):return mapping.get(m.group(),m.group())
 def rewrite(l):
  return re.sub(r'(?<![\w])[_A-Za-z][_A-Za-z0-9]*(?![\w])',renames,l)
 assembly.append(name+':')
 for line in packed.splitlines():
  if line.endswith(':'):assembly.append(mapping[line[:-1]]+':')
  else:assembly.append(rewrite(line))
 for k,v in t.strings.items():
  assembly.append(strs[k]+':')
  assembly.append('    byte '+','.join(str(x) for x in v))
 size_records.append({'name':name,'bytes':info['instruction_bytes'],'temps':info['temporary_values'],'packed_bytes':info['packed_bytes'],'address_hits':b.address_hits,'index_hits':b.index_hits,'a_residency_savings':getattr(b,'avoided_a_loads',0)})

# A precisely specified startup entry, invoked with an externally provided
# source filename and expected 6502 result register ABI A/X.
boot=[
'__experiment_entry:',
# Access all C BSS under $a000-$bfff while leaving KERNAL & I/O mapped.
'    lda $01',
'    and #$fe',
'    sta $01',
'    jsr __nc_init',
'    lda #<__experiment_name',
'    sta __call_ass_assemble_0',
'    lda #>__experiment_name',
'    sta __call_ass_assemble_0+1',
'    lda #$08',
'    sta __call_ass_assemble_1',
'    lda #$00',
'    sta __call_ass_assemble_2',
'    sta __call_ass_assemble_2+1',
'    sta __call_ass_assemble_3',
'    sta __call_ass_assemble_4',
'    sta __call_ass_assemble_4+1',
'    jsr ass_assemble',
'    sta __experiment_status',
'__experiment_stop:',
'    jmp __experiment_stop',
'__experiment_name:',
'    byte '+','.join(str(ord(x)) for x in 'TEST.ASM'),
]
# External runtime must be inserted by link_runtime.py, not inferred.
P.joinpath('functions.asm').write_text('\n'.join(assembly)+'\n')
P.joinpath('boot.asm').write_text('\n'.join(boot)+'\n')
P.joinpath('initialized.json').write_text(json.dumps({n:list(v) for n,v in initialized.items()},indent=2))
P.joinpath('symbols.json').write_text(json.dumps(symbols,indent=2))
P.joinpath('local_storage.json').write_text(json.dumps(local_storage,indent=2))
P.joinpath('sizes.json').write_text(json.dumps(size_records,indent=2))
P.joinpath('layout.json').write_text(json.dumps({'bss_base':BSS_BASE,'bss_end':bss_next,'bss_bytes':bss_next-BSS_BASE,'bss_limit':BSS_LIMIT,'functions':len(funcs),'initialized_bytes':sum(map(len,initialized.values())),'functions_instruction_bytes':sum(x['bytes'] for x in size_records),'max_packed_scratch':global_tempmax,'zp':ZP,'extern':extern},indent=2))
print(json.dumps(json.loads(P.joinpath('layout.json').read_text()),indent=2))
