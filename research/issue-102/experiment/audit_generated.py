import re,json,collections
from pathlib import Path
p=Path(__file__).parent
rows=(p/'compact_image.asm').read_text().splitlines()
sym=json.loads((p/'compact_resolved.json').read_text())
# Proper C-defined functions from exact 44-function C source
source=(p/'full_corpus/ass.c').read_text()
functions=re.findall(r'^(?:char|int|unsigned)\s+(\w+)\s*\([^;{}]*\)\s*\{',source,re.M)
assert len(functions)==44,(len(functions),functions)
functions=list(functions)
limits={n:(sym[n],sym[functions[i+1]] if i<len(functions)-1 else sym['__nc_init']) for i,n in enumerate(functions)}
per={}
all_instr=[]
for i,n in enumerate(functions):
 start=rows.index(n+':')
 end=rows.index((functions[i+1] if i<len(functions)-1 else '__nc_init')+':')
 instructions=[s.strip() for s in rows[start:end] if re.match(r'^\s+[a-z]{3}(?:\s|$)',s)]
 assert all(len(v.split())>=1 for v in instructions)
 counts=collections.Counter(t.split()[0] for t in instructions)
 per[n]={'bytes':limits[n][1]-limits[n][0],'lines':len(instructions),'ops':counts}
 all_instr+= [(n,j,ins) for j,ins in enumerate(instructions)]

C=collections.Counter(ins.split()[0] for _,_,ins in all_instr)
print('functions',len(functions),'bytes',sum(x['bytes'] for x in per.values()),'instructions',len(all_instr))
print('ops',C.most_common(25))
print('top functions')
for name,pd in sorted(per.items(),key=lambda kv:kv[1]['bytes'],reverse=True)[:20]:
 cc=pd['ops'];print(f'{name:<36}{pd["bytes"]:>5} B    {pd["lines"]:>4} ins, {cc["lda"]:>3} LDA, {cc["sta"]:>3} STA, {cc["jmp"]:>2} JMP')

pairs=collections.Counter();frag=collections.Counter();examples=collections.defaultdict(list)
for name in functions:
 start=rows.index(name+':');end=rows.index((functions[functions.index(name)+1] if name!=functions[-1] else '__nc_init')+':')
 ins=[s.strip() for s in rows[start:end] if re.match(r'^\s+[a-z]{3}(?:\s|$)',s)]
 for j in range(len(ins)-1):
  x,y=ins[j:j+2]
  if x.startswith('sta ') and y=='lda '+x[4:]:
   pairs['sta-lda identical']+=1;examples['sta-lda identical'].append((name,j,x,y))
  if x.startswith('lda ') and y=='lda '+x[4:]:
   pairs['lda-lda identical']+=1;examples['lda-lda identical'].append((name,j,x,y))
  if x.startswith('and #$ff'):pairs['and #ff']+=1
  if x.startswith('ora #$00'):pairs['ora #00']+=1
  if x.startswith('lda #$00') and y=='and #$00':pairs['lda0-and0']+=1
  if x=='ldx #$00' and j>0 and ins[j-1]=='ldx #$00':pairs['ldx0-ldx0']+=1
  if len(ins)>=j+3 and re.match(r'sta __tmp\d+',x) and re.match(r'lda __tmp\d+',y) and x[4:]==y[4:]:
   pass
  if (x.startswith('sta __tmp') and y.startswith('lda __tmp') and x[4:]==y[4:]):frag['redundant load of temp']+=1
 for j in range(len(ins)-3):
  x,y,z,w=ins[j:j+4]
  if x.startswith('lda ') and re.fullmatch(r'sta __tmp\d+',y) and z=='lda '+y[4:] and w.startswith('sta '):
   frag['lda src;sta tmp;lda tmp;sta dst']+=1; examples['4gram'].append((name,j,x,y,z,w))
  if re.fullmatch(r'lda #[^\s]+',x) and y=='eor #$80' and z.startswith('sta __rh'):
   frag['signed compare high bias setup']+=1
print('instruction patterns',pairs,frag)
for k,v in examples.items():print('examples',k,v[:5])
print('upper,len',[(n,per[n]['bytes']) for n in ['upper_char','same_text','apply_byte_prefix','hex_nibble','find_opcode','stage_byte','parse_atom','assemble_instruction','process_source_line','resolve_fixups_for_symbol','allocate_symbol','patch_word_chain']])
