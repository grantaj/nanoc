"""Experimental calling convention: pass the final char argument in A.

Rewrites a complete, already-typed 44-function assembly image *before linking*.
We do not assume a static parameter is immutable, that A survives a call,
or that preceding argument evaluation has no effects: replace only the last
adjacent STA to the last-char parameter slot and save A on callee entry.
The callee parameter home otherwise remains unchanged.
"""
from pathlib import Path
from collections import Counter
from pycparser import c_parser,c_ast
import re,json
R=Path(__file__).resolve().parent
src=re.sub(r'/\*.*?\*/','',(R/'full_corpus/ass.c').read_text(),flags=re.S)
tree=c_parser.CParser().parse(src)
params={}
for d in tree.ext:
    if not isinstance(d,c_ast.FuncDef) or not d.decl.type.args:continue
    p=d.decl.type.args.params
    if not p:continue
    last=p[-1]
    if isinstance(last.type,c_ast.TypeDecl) and last.type.type.names==['char']:
       params[d.decl.name]=(len(p)-1,last.name)
lines=(R/'functions.asm').read_text().splitlines()
stats=Counter();have=set();out=[]
for i,line in enumerate(lines):
    m=re.fullmatch(r'\s*jsr\s+(\w+)\s*',line)
    if m and m.group(1) in params:
        f=m.group(1);slot='__call_'+f+'_'+str(params[f][0])
        assert out and out[-1].strip()=='sta '+slot, ('call arg not final A store',f,i,out[-6:])
        out.pop();out.append(line);stats['elided_caller_store']+=1
    elif line.startswith('__F_') and line.endswith('_entry:'):
        m=re.fullmatch(r'__F_(\w+)_entry:',line)
        if m and m.group(1) in params:
            f=m.group(1); assert f not in have
            have.add(f);out.append(line)
            out.append('    sta __L_'+f+'_'+params[f][1]);stats['callee_prologue_store']+=1
        else:out.append(line)
    else:out.append(line)
assert have==set(params),(set(params)-have)
(R/'functions.asm').write_text('\n'.join(out)+'\n')
(R/'arg_a_abi_stats.json').write_text(json.dumps(dict(stats),indent=2))
print(stats)
