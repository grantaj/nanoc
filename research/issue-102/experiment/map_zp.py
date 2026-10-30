"""Upper-bound experiment: relocate hot scalar BSS locals into hypothetically free ZP.
NOT a safe KERNAL memory map or an ABI recommendation. Do not use on actual C64.
"""
from pathlib import Path
from collections import Counter,defaultdict
import json,re,os
from pycparser import c_parser,c_ast
R=Path(__file__).parent
sym=json.loads((R/'symbols.json').read_text());loc=json.loads((R/'local_storage.json').read_text())
s=re.sub(r'/\*.*?\*/','',(R/'full_corpus'/'ass.c').read_text(),flags=re.S)
a=c_parser.CParser().parse(s)
for d in a.ext:
 if not isinstance(d,c_ast.Decl) or d.init is not None:continue
 if isinstance(d.type,c_ast.PtrDecl):loc[d.name]=2
 elif isinstance(d.type,c_ast.TypeDecl):loc[d.name]=1 if d.type.type.names==['char'] else 2
asm=(R/'functions.asm').read_text()
counts=Counter(re.findall(r'(?<![a-zA-Z_0-9])(__L_[a-zA-Z_0-9]+|__call_[a-zA-Z_0-9]+)(?![a-zA-Z_0-9])',asm))
# Attribute usage of static call aliases to the corresponding callee-local byte slots.
usage={k:0 for k in loc if k in sym}
byaddr=defaultdict(list)
for k in usage:byaddr[sym[k]].append(k)
for n,c in counts.items():
 if n in usage:usage[n]+=c
 elif n in sym and n.startswith('__call_'):
  for k in byaddr.get(sym[n],[]):usage[k]+=c
# count raw globals too (including absolute symbolic references)
for n in usage:
 if not n.startswith('__L_'):usage[n]+=len(re.findall(r'(?<![a-zA-Z_0-9])'+re.escape(n)+r'(?![a-zA-Z_0-9])',asm))
# High-value allocation per byte, no overlaps, excluding the original $02..$10 scratch.
items=sorted(usage,key=lambda n:(usage[n]/loc[n],usage[n],n),reverse=True)
ptr=0x11;mapping=[];saved_origin=dict(sym);ZP_LIMIT=0x11+int(os.environ.get("ZP_BUDGET","235"))
for n in items:
 if usage[n]==0:continue
 width=loc[n]
 if ptr+width>ZP_LIMIT:continue
 original=sym[n]
 sym[n]=ptr
 # All aliases of this BSS slot (including call slots) must follow it.
 for k in saved_origin:
  if k.startswith('__call_') and saved_origin[k]==original:sym[k]=ptr
 mapping.append({'symbol':n,'old':original,'zp':ptr,'width':width,'refs':usage[n]})
 ptr+=width
assert ptr<=0xfc
(R/'symbols.json').write_text(json.dumps(sym,indent=2))
(R/'zp_mapping.json').write_text(json.dumps(mapping,indent=2))
print('occupied',ptr-0x11,'bytes for',len(mapping),'variables; references',sum(x['refs'] for x in mapping))
print('top 10',[(x['symbol'],x['refs']) for x in mapping[:10]])
