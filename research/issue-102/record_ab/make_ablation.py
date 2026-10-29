from pathlib import Path
import shutil,re
R=Path(__file__).parent
original=(R/'original_ass.c').read_text()
combined=(R/'work/full_corpus/ass.c').read_text()

def fbody(src,n):
 m=re.search(r'\n(?:char|int|unsigned) '+re.escape(n)+r'\([^;]*?\)\n\{',src,re.S)
 assert m,n
 start=m.start()+1;pos=m.end();level=1
 while level:
  c=src[pos];level+=(c=='{')-(c=='}');pos+=1
 return src[start:pos]
def putfun(src,body,name):
 prev=fbody(src,name)
 assert src.count(prev)==1
 return src.replace(prev,body)

def transform(symbols,fixups):
 src=combined
 if not symbols:
  src=src.replace('''/* Source-algorithm control: one persistent variable-length record arena.
 * A symbol handle is its stable byte offset in symbol_records.
 * Record: length, payload_lo, payload_hi, kind, scope, name bytes.
 */
char symbol_records[13824];
int symbol_records_used;
int symbol_count;
int symbol_name_used;
char current_scope;''','''int symbol_name_offset[896];
char symbol_name_length[896];
unsigned symbol_payload[896];
char symbol_scope[896];
char symbol_kind[896];
char symbol_name_bytes[9344];
int symbol_count;
int symbol_name_used;
char current_scope;''')
  for n in ('find_symbol','allocate_symbol','intern_label','define_label','all_symbols_defined','stage_plain_word_reference','parse_atom'):
   src=putfun(src,fbody(original,n),n)
  src=src.replace('    symbol_records_used = 0;\n','')
 if not fixups:
  src=src.replace('''/* Fixed-size packed fixups, traversed with a real pointer cursor.
 * kind, stage_lo, stage_hi, symbol_lo, symbol_hi,
 * addend_lo, addend_hi, prefix.
 */
char fixup_records[5120];
char *fixup_next;
int fixup_count;''','''char fixup_kind[640];
int fixup_stage[640];
int fixup_symbol[640];
unsigned fixup_addend[640];
char fixup_prefix[640];
int fixup_count;''')
  for n in ('append_fixup','trim_fixups','resolve_fixups_for_symbol','all_fixups_resolved'):
   src=putfun(src,fbody(original,n),n)
  src=src.replace('    fixup_next = fixup_records;\n','')
 if symbols and not fixups:
  src=src.replace('value = (symbol_payload[symbol] + fixup_addend[i]) & 65535;', 'value = ((symbol_records[symbol + 1] | (symbol_records[symbol + 2] << 8)) + fixup_addend[i]) & 65535;')
 if fixups and not symbols:
  src=src.replace('    char *symbol_entry;\n','').replace('    symbol_entry = symbol_records + symbol;\n','').replace('value = (symbol_entry[1] | (symbol_entry[2] << 8));', 'value = symbol_payload[symbol];')
 assert ('symbol_records[' in src) == symbols
 assert ('fixup_records[' in src) == fixups
 return src
for tag,sym,fix in [('symbol_only',True,False),('fixup_only',False,True)]:
 d=R/tag;shutil.copytree(R/'work',d,dirs_exist_ok=True)
 src=transform(sym,fix)
 for f in ('ass.c','exact_source/ass.c'):(d/'full_corpus'/f).write_text(src)
 print(tag,len(src))
