from pathlib import Path
import re
srcpath=Path(__file__).parent/'work/full_corpus/ass.c'
src=srcpath.read_text()

def replace(needle,new):
 global src
 assert src.count(needle)==1,(needle[:80],src.count(needle))
 src=src.replace(needle,new)
def function(name,new):
 global src
 m=re.search(r'\n(?:char|int|unsigned) '+re.escape(name)+r'\([^;]*?\)\n\{',src,re.S)
 assert m,name
 pos=m.end(); level=1
 while level:
  c=src[pos];level+= (c=='{')-(c=='}');pos+=1
 src=src[:m.start()+1]+new.strip()+src[pos:]

replace('''int symbol_name_offset[896];
char symbol_name_length[896];
unsigned symbol_payload[896];
char symbol_scope[896];
char symbol_kind[896];
char symbol_name_bytes[9344];
int symbol_count;
int symbol_name_used;
char current_scope;

char fixup_kind[640];
int fixup_stage[640];
int fixup_symbol[640];
unsigned fixup_addend[640];
char fixup_prefix[640];
int fixup_count;''','''/* Source-algorithm control: one persistent variable-length record arena.
 * A symbol handle is its stable byte offset in symbol_records.
 * Record: length, payload_lo, payload_hi, kind, scope, name bytes.
 */
char symbol_records[13824];
int symbol_records_used;
int symbol_count;
int symbol_name_used;
char current_scope;

/* Fixed-size packed fixups, traversed with a real pointer cursor.
 * kind, stage_lo, stage_hi, symbol_lo, symbol_hi,
 * addend_lo, addend_hi, prefix.
 */
char fixup_records[5120];
char *fixup_next;
int fixup_count;''')
function('append_fixup','''
char append_fixup(char kind, int stage, int symbol, unsigned addend, char prefix)
{
    char *record;
    if (fixup_count >= 640) {
        return ASSEMBLE_WORK_FULL;
    }
    record = fixup_next;
    record[0] = kind;
    record[1] = stage & 255;
    record[2] = (stage >> 8) & 255;
    record[3] = symbol & 255;
    record[4] = (symbol >> 8) & 255;
    record[5] = addend & 255;
    record[6] = (addend >> 8) & 255;
    record[7] = prefix;
    fixup_next = record + 8;
    fixup_count = fixup_count + 1;
    return ASSEMBLE_OK;
}
''')
function('trim_fixups','''
char trim_fixups()
{
    char *record;
    while (fixup_count > 0) {
        record = fixup_next - 8;
        if (record[0] != FIXUP_NONE) {
            return ASSEMBLE_OK;
        }
        fixup_next = record;
        fixup_count = fixup_count - 1;
    }
    return ASSEMBLE_OK;
}
''')
function('resolve_fixups_for_symbol','''
char resolve_fixups_for_symbol(int symbol)
{
    char *record;
    char *symbol_entry;
    char kind;
    unsigned value;
    int stage;
    int relative;

    symbol_entry = symbol_records + symbol;
    record = fixup_records;
    while (record < fixup_next) {
        kind = record[0];
        if (kind != FIXUP_NONE) {
            if ((record[3] | (record[4] << 8)) == symbol) {
                value = (symbol_entry[1] | (symbol_entry[2] << 8));
                value = (value + record[5] + (record[6] << 8)) & 65535;
                if (record[7] != VALUE_PREFIX_NONE) {
                    value = apply_byte_prefix(value, record[7]);
                }
                stage = record[1] | (record[2] << 8);
                if (kind == FIXUP_WORD) {
                    ass_image[stage] = value & 255;
                    ass_image[stage + 1] = (value >> 8) & 255;
                } else {
                    if (kind == FIXUP_RELATIVE) {
                        relative = relative_byte(value, (ass_origin + stage + 1) & 65535);
                        if (relative < 0) {
                            return ASSEMBLE_EMIT_ERROR;
                        }
                        ass_image[stage] = relative;
                    } else {
                        if (value > 255) {
                            if (kind == FIXUP_DATA_BYTE) {
                                return ASSEMBLE_BAD_DATA;
                            }
                            return ASSEMBLE_EMIT_ERROR;
                        }
                        ass_image[stage] = value;
                    }
                }
                record[0] = FIXUP_NONE;
            }
        }
        record = record + 8;
    }
    return trim_fixups();
}
''')
function('find_symbol','''
int find_symbol(char *name, char length)
{
    int wanted_scope;
    int i;
    int offset;
    char j;
    char same;
    char *record;

    wanted_scope = scope_for_name(name, length);
    if (wanted_scope < 0) {
        return -2;
    }
    record = symbol_records;
    offset = 0;
    i = 0;
    while (i < symbol_count) {
        if (record[4] == wanted_scope) {
            if (record[0] == length) {
                same = 1;
                j = 0;
                while (j < length) {
                    if (record[5 + j] != name[j]) {
                        same = 0;
                    }
                    j = j + 1;
                }
                if (same != 0) {
                    return offset;
                }
            }
        }
        offset = offset + record[0] + 5;
        record = record + record[0] + 5;
        i = i + 1;
    }
    return -1;
}
''')
function('allocate_symbol','''
int allocate_symbol(char *name, char length, char kind, unsigned payload)
{
    int scope;
    int offset;
    char i;
    char *record;

    scope = scope_for_name(name, length);
    if (scope < 0) {
        return -2;
    }
    if (symbol_count >= 896) {
        return -3;
    }
    if (symbol_name_used + length > 9344) {
        return -3;
    }
    offset = symbol_records_used;
    record = symbol_records + offset;
    record[0] = length;
    record[1] = payload & 255;
    record[2] = (payload >> 8) & 255;
    record[3] = kind;
    record[4] = scope;
    i = 0;
    while (i < length) {
        record[5 + i] = name[i];
        i = i + 1;
    }
    symbol_name_used = symbol_name_used + length;
    symbol_records_used = offset + length + 5;
    symbol_count = symbol_count + 1;
    return offset;
}
''')
# Rewrite other symbol uses to pointer field access. We do not generate helper C calls:
# one stable pointer local is materialized for each operation's region.
function('intern_label','''
int intern_label(char *name, char length)
{
    int symbol;
    char *record;
    symbol = find_symbol(name, length);
    if (symbol >= 0) {
        record = symbol_records + symbol;
        if (record[3] == SYMBOL_CONSTANT) {
            return -4;
        }
        return symbol;
    }
    if (symbol == -2) {
        return -2;
    }
    return allocate_symbol(name, length, SYMBOL_LABEL_UNDEFINED, 0);
}
''')
function('define_label','''
char define_label(char *name, char length, unsigned value)
{
    int symbol;
    int old_head;
    char status;
    char *record;

    symbol = find_symbol(name, length);
    if (symbol == -2) {
        return ASSEMBLE_SCOPE_ERROR;
    }
    if (symbol < 0) {
        symbol = allocate_symbol(name, length, SYMBOL_LABEL_DEFINED, value);
        if (symbol == -2) {
            return ASSEMBLE_SCOPE_ERROR;
        }
        if (symbol < 0) {
            return ASSEMBLE_SYMBOL_FULL;
        }
        return ASSEMBLE_OK;
    }
    record = symbol_records + symbol;
    if (record[3] != SYMBOL_LABEL_UNDEFINED) {
        return ASSEMBLE_BAD_SYMBOL;
    }
    old_head = record[1] | (record[2] << 8);
    record[1] = value & 255;
    record[2] = (value >> 8) & 255;
    record[3] = SYMBOL_LABEL_DEFINED;
    status = patch_word_chain(old_head, value);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    return resolve_fixups_for_symbol(symbol);
}
''')
# Parse_atom: need pre-existing locals and one record pointer; injection near function start.
assert src.count('if (symbol_kind[symbol] == SYMBOL_LABEL_UNDEFINED)')==1
src=src.replace('if (symbol_kind[symbol] == SYMBOL_LABEL_UNDEFINED)', 'if (symbol_records[symbol + 3] == SYMBOL_LABEL_UNDEFINED)')
src=src.replace('atom_value = symbol_payload[symbol];','atom_value = symbol_records[symbol + 1] | (symbol_records[symbol + 2] << 8);')
function('stage_plain_word_reference','''
char stage_plain_word_reference(int symbol)
{
    int stage;
    int old_head;
    char status;
    char *record;

    record = symbol_records + symbol;
    stage = ass_image_length;
    old_head = record[1] | (record[2] << 8);
    status = stage_byte(old_head & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    status = stage_byte((old_head >> 8) & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    record[1] = (stage + 1) & 255;
    record[2] = ((stage + 1) >> 8) & 255;
    return ASSEMBLE_OK;
}
''')
replace('''    symbol_count = 0;
    symbol_name_used = 0;
    current_scope = 0;
    fixup_count = 0;''','''    symbol_count = 0;
    symbol_name_used = 0;
    symbol_records_used = 0;
    current_scope = 0;
    fixup_count = 0;
    fixup_next = fixup_records;''')
function('all_symbols_defined','''
char all_symbols_defined()
{
    int i;
    char *record;
    i = 0;
    record = symbol_records;
    while (i < symbol_count) {
        if (record[3] == SYMBOL_LABEL_UNDEFINED) {
            return 0;
        }
        record = record + record[0] + 5;
        i = i + 1;
    }
    return 1;
}
''')
function('all_fixups_resolved','''
char all_fixups_resolved()
{
    char *record;
    record = fixup_records;
    while (record < fixup_next) {
        if (record[0] != FIXUP_NONE) {
            return 0;
        }
        record = record + 8;
    }
    return 1;
}
''')
assert 'symbol_payload[' not in src
assert 'symbol_kind[' not in src
assert 'fixup_kind[' not in src
srcpath.write_text(src)
(srcpath.parent/'exact_source'/'ass.c').write_text(src)
print('Rewrote C source',len(src),'chars')
