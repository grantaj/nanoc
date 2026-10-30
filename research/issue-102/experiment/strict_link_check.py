"""Check every physically placed function with exact bootstrap/ass.c host assembler.
A synthetic equate for external symbols uses *the actual computed linked address*.
No private replica assembler in this validation stage.
"""
from pathlib import Path
from collections import Counter
from pycparser import c_parser,c_ast
import subprocess,re,json
R=Path(__file__).parent;S=R/'full_corpus'
functions=[x.decl.name for x in c_parser.CParser().parse(re.sub(r'/\*.*?\*/','',(S/'ass.c').read_text(),flags=re.S)).ext if isinstance(x,c_ast.FuncDef)]
ls=(R/'compact_image.asm').read_text().splitlines()
lookup={v:i for i,v in enumerate(ls) if v.endswith(':') and v[:-1] in functions}
symbols=json.loads((R/'compact_resolved.json').read_text())
folder=R/'strict_files';folder.mkdir(exist_ok=True)
results=[]
for i,func in enumerate(functions):
 start=lookup[func+':']
 stop=lookup[functions[i+1]+':'] if i+1<len(functions) else next(j for j in range(start+1,len(ls)) if ls[j]=='__nc_init:')
 chunk=ls[start:stop]
 defined={l.strip()[:-1] for l in chunk if l.strip().endswith(':')}
 external=set()
 for line in chunk:
  s=line.split(';')[0].strip()
  if not s or s.endswith(':') or s.startswith('byte '):continue
  _,_,arg=s.partition(' ')
  arg=arg.strip().lstrip('#').lstrip('<>').replace('(','').replace(')','')
  arg=re.sub(r',([xy])$', '',arg)
  a=re.fullmatch(r'([A-Za-z_][A-Za-z_0-9]*)(?:\+\d+)?',arg)
  if a and a.group(1) not in defined:external.add(a.group(1))
 for e in external:
  if e not in symbols:raise ValueError(('missing external',func,e))
 defs=[f'{name} = ${((symbols[symbols[name]] if isinstance(symbols[name],str) else symbols[name])):04x}' for name in sorted(external)]
 code='* = $0800\n'+'\n'.join(defs)+'\n'+'\n'.join(chunk)+'\n'
 out=folder/(func+'.asm');out.write_text(code)
 p=subprocess.run([str(S/'host_assembler'),str(out.relative_to(S)) if out.is_relative_to(S) else str(out)],cwd=S,text=True,capture_output=True)
 # Host's native bootstrap/ass.c parser does not accept full absolute paths > ?
 m=re.search(r'assembled (\d+) bytes',p.stdout)
 expected=(symbols[functions[i+1]] if i+1<len(functions) else symbols['__nc_init'])-symbols[func]
 observed=int(m.group(1)) if m else -1
 results.append((func,expected,observed,p.returncode,p.stderr.strip()[:300]))
 print(f'{i+1:02d}/44 {func:32s} expected={expected:5d} assembled={observed:5d} status={p.returncode}',flush=True)
 if observed!=expected or p.returncode:print('DIAGNOSTIC',p.stderr, p.stdout[:500],flush=True);break
(R/'strict_check.json').write_text(json.dumps({'total':len(results),'passed':sum(x[1]==x[2] and not x[3] for x in results),'entries':results},indent=2))
assert len(results)==len(functions) and all(x[1]==x[2] and not x[3] for x in results)
print('STRICT REAL ASS.C: 44/44 functions length-matched physical image')
