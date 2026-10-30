/*
 * Native-structured Nano C Phase 1 assembler (experimental).
 *
 * This is a separate, native-algorithm alternative to bootstrap/ass.c.
 * Symbol names live in packed variable-length records, local names use a
 * rewindable arena, and exceptional fixups are packed eight-byte records.
 * The ordinary C parser, opcode tables, source reader and public entry point
 * are retained so that each migration can be compared against the baseline.
 *
 * This file is intentionally written in a small C subset.  It is a language
 * discovery program, not a host-specific assembler implementation.  The host
 * validation adapter supplies io_open/io_read/io_close before including this
 * file.
 *
 * The candidate now uses the frozen Phase 1 integer widths explicitly where a
 * modern host's wider int would otherwise hide 16-bit machine semantics.
 *
 * Deliberately not used here:
 *   struct, union, enum, typedef, const, static, sizeof
 *   for, switch, do, goto, continue
 *   ++, --, ?:, casts, function pointers
 *   malloc, stdio, headers or preprocessing
 *
 * The useful subset exercised here is recorded in phase1-notes.md.
 */

/* Status values match the native assembler where useful. */
char ASSEMBLE_OK = 0;
char ASSEMBLE_BAD_STATEMENT = 1;
char ASSEMBLE_BAD_SYMBOL = 2;
char ASSEMBLE_SYMBOL_FULL = 3;
char ASSEMBLE_SCOPE_ERROR = 4;
char ASSEMBLE_BAD_INSTRUCTION = 5;
char ASSEMBLE_UNDEFINED = 6;
char ASSEMBLE_EMIT_ERROR = 7;
char ASSEMBLE_BAD_DATA = 9;
char ASSEMBLE_BAD_ORIGIN = 10;
char ASSEMBLE_WORK_FULL = 11;
char ASSEMBLE_IO_ERROR = 12;
char ASSEMBLE_LINE_TOO_LONG = 13;
char ASSEMBLE_INCLUDE_DEPTH = 14;

/*
 * Addressing modes use the same numbering as dis/mode_ids.inc.
 *
 * 0 implied       1 accumulator   2 immediate
 * 3 zero page     4 zero page,X   5 zero page,Y
 * 6 absolute      7 absolute,X    8 absolute,Y
 * 9 indirect     10 (zp,X)       11 (zp),Y
 * 12 relative    13 undocumented
 */
char MODE_IMPLIED = 0;
char MODE_ACCUMULATOR = 1;
char MODE_IMMEDIATE = 2;
char MODE_ZERO_PAGE = 3;
char MODE_ZERO_PAGE_X = 4;
char MODE_ZERO_PAGE_Y = 5;
char MODE_ABSOLUTE = 6;
char MODE_ABSOLUTE_X = 7;
char MODE_ABSOLUTE_Y = 8;
char MODE_INDIRECT = 9;
char MODE_INDIRECT_X = 10;
char MODE_INDIRECT_Y = 11;
char MODE_RELATIVE = 12;

char mode_width[14] = {0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 1, 1, 1, 0};

/* Three bytes per mnemonic, in the same order as dis/mnemonic_table.asm. */
char mnemonic_table[172] =
    "ADCANDASLBCCBCSBEQBITBMIBNEBPLBRKBVCBVSCLCCLDCLICLVCMPCPXCPYDECDEXDEYEORINCINXINYJMPJSRLDALDXLDYLSRNOPORAPHAPHPPLAPLPROLRORRTIRTSSBCSECSEDSEISTASTXSTYTAXTAYTSXTXATXSTYA???";

/*
 * One authoritative 256-entry encoding table, represented as parallel byte
 * arrays because Phase 1 is not assumed to have structures.
 * Undocumented entries use mnemonic 56 / mode 13.
 */
char opcode_mnemonic[256] = {
    10, 34, 56, 56, 56, 34, 2, 56, 36, 34, 2, 56, 56, 34, 2, 56,
    9, 34, 56, 56, 56, 34, 2, 56, 13, 34, 56, 56, 56, 34, 2, 56,
    28, 1, 56, 56, 6, 1, 39, 56, 38, 1, 39, 56, 6, 1, 39, 56,
    7, 1, 56, 56, 56, 1, 39, 56, 44, 1, 56, 56, 56, 1, 39, 56,
    41, 23, 56, 56, 56, 23, 32, 56, 35, 23, 32, 56, 27, 23, 32, 56,
    11, 23, 56, 56, 56, 23, 32, 56, 15, 23, 56, 56, 56, 23, 32, 56,
    42, 0, 56, 56, 56, 0, 40, 56, 37, 0, 40, 56, 27, 0, 40, 56,
    12, 0, 56, 56, 56, 0, 40, 56, 46, 0, 56, 56, 56, 0, 40, 56,
    56, 47, 56, 56, 49, 47, 48, 56, 22, 56, 53, 56, 49, 47, 48, 56,
    3, 47, 56, 56, 49, 47, 48, 56, 55, 47, 54, 56, 56, 47, 56, 56,
    31, 29, 30, 56, 31, 29, 30, 56, 51, 29, 50, 56, 31, 29, 30, 56,
    4, 29, 56, 56, 31, 29, 30, 56, 16, 29, 52, 56, 31, 29, 30, 56,
    19, 17, 56, 56, 19, 17, 20, 56, 26, 17, 21, 56, 19, 17, 20, 56,
    8, 17, 56, 56, 56, 17, 20, 56, 14, 17, 56, 56, 56, 17, 20, 56,
    18, 43, 56, 56, 18, 43, 24, 56, 25, 43, 33, 56, 18, 43, 24, 56,
    5, 43, 56, 56, 56, 43, 24, 56, 45, 43, 56, 56, 56, 43, 24, 56
};

char opcode_mode[256] = {
    0, 10, 13, 13, 13, 3, 3, 13, 0, 2, 1, 13, 13, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13,
    6, 10, 13, 13, 3, 3, 3, 13, 0, 2, 1, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13,
    0, 10, 13, 13, 13, 3, 3, 13, 0, 2, 1, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13,
    0, 10, 13, 13, 13, 3, 3, 13, 0, 2, 1, 13, 9, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13,
    13, 10, 13, 13, 3, 3, 3, 13, 0, 13, 0, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 4, 4, 5, 13, 0, 8, 0, 13, 13, 7, 13, 13,
    2, 10, 2, 13, 3, 3, 3, 13, 0, 2, 0, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 4, 4, 5, 13, 0, 8, 0, 13, 7, 7, 8, 13,
    2, 10, 13, 13, 3, 3, 3, 13, 0, 2, 0, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13,
    2, 10, 13, 13, 3, 3, 3, 13, 0, 2, 0, 13, 6, 6, 6, 13,
    12, 11, 13, 13, 13, 4, 4, 13, 0, 8, 13, 13, 13, 7, 7, 13
};

/* Native-oriented workspaces. The arena grows from opposite ends.
 * Global symbols append from 0; local symbols prepend from the end and are
 * discarded at the next global label, after checking unresolved locals.
 *
 * [length, payload-low, payload-high, kind, name bytes...]
 * An undefined label's payload is the head of its staged word-reference chain.
 * Offsets into this arena serve as stable symbol handles (non-negative int).
 * They deliberately replace numeric symbol indexes in the old C assembler.
 */
char ass_image[11264];
int ass_image_length;
char *stage_cursor;
unsigned assembly_pc;
unsigned ass_origin;

char source_line[256];
char source_line_length;
char source_path[256];
char source_handle[5];
char source_eof_pending[5];
int source_depth;
char *source_directory;
char source_directory_length;

char symbol_records[15616];
int symbol_global_end;
int symbol_local_start;
int symbol_count;
int symbol_local_count;
char current_scope;

/* Exceptional fixups: kind, stage(lo,hi), symbol(lo,hi), addend(lo,hi), prefix.
 * Ordinary unresolved word operands remain chained in the staged image.
 */
char fixup_records[5120];
int fixup_end;

/* Symbol kinds. */
char SYMBOL_CONSTANT = 0;
char SYMBOL_LABEL_UNDEFINED = 1;
char SYMBOL_LABEL_DEFINED = 2;

/* Value parser results. */
char VALUE_OK = 0;
char VALUE_UNRESOLVED = 1;
char VALUE_BAD = 2;
char VALUE_SYMBOL_FULL = 3;
char VALUE_SCOPE_ERROR = 4;

char VALUE_PREFIX_NONE = 0;
char VALUE_PREFIX_LOW = 1;
char VALUE_PREFIX_HIGH = 2;

unsigned value_result;
int captured_symbol;
unsigned captured_addend;
char captured_prefix;

unsigned atom_value;
int atom_symbol;
char atom_used;
char atom_kind;

/* Fixup kinds. */
char FIXUP_NONE = 0;
char FIXUP_BYTE = 1;
char FIXUP_WORD = 2;
char FIXUP_RELATIVE = 3;
char FIXUP_DATA_BYTE = 4;

char origin_allowed;

/* ---------------- Small text/value helpers ---------------- */

char upper_char(char c)
{
    if (c >= 'a') {
        if (c <= 'z') {
            return c - 32;
        }
    }
    return c;
}

char same_text(char *a, char a_length, char *b, char b_length)
{
    char i;

    if (a_length != b_length) {
        return 0;
    }

    i = 0;
    while (i < a_length) {
        if (a[i] != b[i]) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

char apply_byte_prefix(unsigned value, char prefix)
{
    value = value & 65535;
    if (prefix == VALUE_PREFIX_LOW) {
        return value & 255;
    }
    return (value >> 8) & 255;
}

int hex_nibble(char c)
{
    c = upper_char(c);
    if (c >= '0') {
        if (c <= '9') {
            return c - '0';
        }
    }
    if (c >= 'A') {
        if (c <= 'F') {
            return c - 'A' + 10;
        }
    }
    return -1;
}

/* ---------------- Exceptional forward fixups ---------------- */

unsigned symbol_payload_at(int entry);

char append_fixup(char kind, int stage, int symbol, unsigned addend, char prefix)
{
    char *record;

    if (fixup_end >= 5120) {
        return ASSEMBLE_WORK_FULL;
    }
    record = fixup_records + fixup_end;
    record[0] = kind;
    record[1] = stage & 255;
    record[2] = (stage >> 8) & 255;
    record[3] = symbol & 255;
    record[4] = (symbol >> 8) & 255;
    record[5] = addend & 255;
    record[6] = (addend >> 8) & 255;
    record[7] = prefix;
    fixup_end = fixup_end + 8;
    return ASSEMBLE_OK;
}

int relative_byte(unsigned target, unsigned base)
{
    unsigned difference;

    difference = (target - base) & 65535;
    if (difference <= 127) {
        return difference;
    }
    if (difference >= 65408) {
        return difference & 255;
    }
    return -1;
}

char trim_fixups()
{
    while (fixup_end != 0) {
        if (fixup_records[fixup_end - 8] != FIXUP_NONE) {
            return ASSEMBLE_OK;
        }
        fixup_end = fixup_end - 8;
    }
    return ASSEMBLE_OK;
}

/* Walk the same eight-byte records that append_fixup emits. */
char resolve_fixups_for_symbol(int symbol)
{
    int position;
    char *record;
    char kind;
    unsigned value;
    int stage;
    int relative;

    position = 0;
    while (position < fixup_end) {
        record = fixup_records + position;
        kind = record[0];
        if (kind != FIXUP_NONE) {
            if ((record[3] | (record[4] << 8)) == symbol) {
                value = (symbol_payload_at(symbol) +
                    (record[5] | (record[6] << 8))) & 65535;
                if (record[7] != VALUE_PREFIX_NONE) {
                    value = apply_byte_prefix(value, record[7]);
                }
                stage = record[1] | (record[2] << 8);

                if (kind == FIXUP_WORD) {
                    ass_image[stage] = value & 255;
                    ass_image[stage + 1] = (value >> 8) & 255;
                } else {
                    if (kind == FIXUP_RELATIVE) {
                        relative = relative_byte(
                            value, (ass_origin + stage + 1) & 65535
                        );
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
        position = position + 8;
    }
    return trim_fixups();
}

/* ---------------- Native-style packed symbol arena ---------------- */

/* The record's payload is a value if defined, or a forward chain if not. */
unsigned symbol_payload_at(int record_at)
{
    char *record;
    record = symbol_records + record_at;
    return record[1] | (record[2] << 8);
}

char symbol_kind_at(int record_at)
{
    return symbol_records[record_at + 3];
}

char symbol_set_payload(int record_at, unsigned value)
{
    char *record;
    record = symbol_records + record_at;
    record[1] = value & 255;
    record[2] = (value >> 8) & 255;
    return 0;
}

char symbol_set_kind(int record_at, char kind)
{
    symbol_records[record_at + 3] = kind;
    return 0;
}

int scope_for_name(char *name, char length)
{
    if (length == 0) {
        return -1;
    }
    if (name[0] == '.') {
        if (current_scope == 0) {
            return -1;
        }
        return current_scope;
    }
    return 0;
}

/* A global symbol is found only in the persistent arena; a dot-prefixed
 * symbol is found only in the current local lifetime. This avoids storing
 * a redundant scope byte in every symbol record. */
int find_symbol(char *name, char length)
{
    int scope;
    int position;
    int limit;
    char *record;
    char j;

    scope = scope_for_name(name, length);
    if (scope < 0) {
        return -2;
    }
    if (scope == 0) {
        position = 0;
        limit = symbol_global_end;
    } else {
        position = symbol_local_start;
        limit = 15616;
    }

    while (position < limit) {
        record = symbol_records + position;
        if (record[0] == length) {
            j = 0;
            while (j < length) {
                if (record[4 + j] != name[j]) {
                    break;
                }
                j = j + 1;
            }
            if (j == length) {
                return position;
            }
        }
        position = position + 4 + record[0];
    }
    return -1;
}

/* Append globals; prepend locals. Neither kind moves while it is live. */
int allocate_symbol(char *name, char length, char kind, unsigned payload)
{
    int scope;
    int record_at;
    int size;
    char *record;
    char i;

    scope = scope_for_name(name, length);
    if (scope < 0) {
        return -2;
    }
    size = 4 + length;
    if (symbol_count >= 896) {
        return -3;
    }
    if (symbol_global_end + size > symbol_local_start) {
        return -3;
    }

    if (scope == 0) {
        record_at = symbol_global_end;
        symbol_global_end = symbol_global_end + size;
    } else {
        symbol_local_start = symbol_local_start - size;
        record_at = symbol_local_start;
        symbol_local_count = symbol_local_count + 1;
    }
    record = symbol_records + record_at;
    record[0] = length;
    record[1] = payload & 255;
    record[2] = (payload >> 8) & 255;
    record[3] = kind;
    i = 0;
    while (i < length) {
        record[4 + i] = name[i];
        i = i + 1;
    }
    symbol_count = symbol_count + 1;
    return record_at;
}

/* Native local-scope boundary: only reclaim after all local labels resolve. */
char all_local_labels_defined()
{
    int position;
    position = symbol_local_start;
    while (position < 15616) {
        if (symbol_kind_at(position) == SYMBOL_LABEL_UNDEFINED) {
            return 0;
        }
        position = position + 4 + symbol_records[position];
    }
    return 1;
}

char rewind_local_symbols()
{
    if (all_local_labels_defined() == 0) {
        return ASSEMBLE_UNDEFINED;
    }
    symbol_local_start = 15616;
    symbol_count = symbol_count - symbol_local_count;
    symbol_local_count = 0;
    return ASSEMBLE_OK;
}

int intern_label(char *name, char length)
{
    int symbol;

    symbol = find_symbol(name, length);
    if (symbol >= 0) {
        if (symbol_kind_at(symbol) == SYMBOL_CONSTANT) {
            return -4;
        }
        return symbol;
    }
    if (symbol == -2) {
        return -2;
    }
    return allocate_symbol(name, length, SYMBOL_LABEL_UNDEFINED, 0);
}

char define_constant(char *name, char length, unsigned value)
{
    int symbol;

    symbol = find_symbol(name, length);
    if (symbol >= 0) {
        return ASSEMBLE_BAD_SYMBOL;
    }
    if (symbol == -2) {
        return ASSEMBLE_SCOPE_ERROR;
    }

    symbol = allocate_symbol(name, length, SYMBOL_CONSTANT, value);
    if (symbol == -2) {
        return ASSEMBLE_SCOPE_ERROR;
    }
    if (symbol < 0) {
        return ASSEMBLE_SYMBOL_FULL;
    }
    return ASSEMBLE_OK;
}

char patch_word_chain(int head, unsigned value)
{
    int stage;
    int next;

    while (head != 0) {
        stage = head - 1;
        next = ass_image[stage] | (ass_image[stage + 1] << 8);
        ass_image[stage] = value & 255;
        ass_image[stage + 1] = (value >> 8) & 255;
        head = next;
    }
    return ASSEMBLE_OK;
}

char define_label(char *name, char length, unsigned value)
{
    int symbol;
    int old_head;
    char status;

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

    if (symbol_kind_at(symbol) != SYMBOL_LABEL_UNDEFINED) {
        return ASSEMBLE_BAD_SYMBOL;
    }

    old_head = symbol_payload_at(symbol);
    symbol_set_payload(symbol, value & 65535);
    symbol_set_kind(symbol, SYMBOL_LABEL_DEFINED);

    status = patch_word_chain(old_head, value);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    return resolve_fixups_for_symbol(symbol);
}

/* ---------------- Tiny assembler value grammar ---------------- */

char parse_atom(char *text, char length)
{
    char i;
    int digit;
    unsigned value;
    int symbol;

    atom_used = 0;
    if (length == 0) {
        return VALUE_BAD;
    }

    if (text[0] == '$') {
        i = 1;
        value = 0;
        while (i < length) {
            if (text[i] == '+') {
                break;
            } else {
                if (text[i] == '-') {
                    break;
                } else {
                    digit = hex_nibble(text[i]);
                    if (digit < 0) {
                        return VALUE_BAD;
                    }
                    if (atom_used >= 4) {
                        return VALUE_BAD;
                    }
                    value = ((value << 4) | digit) & 65535;
                    atom_used = atom_used + 1;
                    i = i + 1;
                }
            }
        }
        if (atom_used == 0) {
            return VALUE_BAD;
        }
        atom_used = atom_used + 1;
        atom_value = value;
        atom_kind = 0;
        return VALUE_OK;
    }

    if (text[0] == 39) {
        if (length < 3) {
            return VALUE_BAD;
        }
        if (text[2] != 39) {
            return VALUE_BAD;
        }
        atom_value = text[1];
        atom_used = 3;
        atom_kind = 0;
        return VALUE_OK;
    }

    if (text[0] >= '0') {
        if (text[0] <= '9') {
            i = 0;
            value = 0;
            while (i < length) {
                if (text[i] == '+') {
                    break;
                } else {
                    if (text[i] == '-') {
                        break;
                    } else {
                        if (text[i] < '0') {
                            return VALUE_BAD;
                        }
                        if (text[i] > '9') {
                            return VALUE_BAD;
                        }
                        value = (value * 10 + text[i] - '0') & 65535;
                        atom_used = atom_used + 1;
                        i = i + 1;
                    }
                }
            }
            atom_value = value;
            atom_kind = 0;
            return VALUE_OK;
        }
    }

    i = 0;
    while (i < length) {
        if (text[i] == '+') {
            break;
        } else {
            if (text[i] == '-') {
                break;
            } else {
                atom_used = atom_used + 1;
                i = i + 1;
            }
        }
    }
    if (atom_used == 0) {
        return VALUE_BAD;
    }

    symbol = find_symbol(text, atom_used);
    if (symbol == -2) {
        return VALUE_SCOPE_ERROR;
    }
    if (symbol < 0) {
        symbol = intern_label(text, atom_used);
        if (symbol == -2) {
            return VALUE_SCOPE_ERROR;
        }
        if (symbol == -3) {
            return VALUE_SYMBOL_FULL;
        }
        if (symbol < 0) {
            return VALUE_BAD;
        }
    }

    if (symbol_kind_at(symbol) == SYMBOL_LABEL_UNDEFINED) {
        atom_symbol = symbol;
        atom_kind = 1;
        return VALUE_UNRESOLVED;
    }

    atom_value = symbol_payload_at(symbol);
    atom_kind = 0;
    return VALUE_OK;
}

char parse_value(char *text, char length)
{
    char position;
    char status;
    char first_kind;
    unsigned first_value;
    int first_symbol;
    char operation;
    char second_kind;

    captured_symbol = -1;
    captured_addend = 0;
    captured_prefix = VALUE_PREFIX_NONE;

    if (length == 0) {
        return VALUE_BAD;
    }

    position = 0;
    if (text[position] == '<') {
        captured_prefix = VALUE_PREFIX_LOW;
        position = position + 1;
    } else {
        if (text[position] == '>') {
            captured_prefix = VALUE_PREFIX_HIGH;
            position = position + 1;
        }
    }

    status = parse_atom(text + position, length - position);
    if (status != VALUE_OK) {
        if (status != VALUE_UNRESOLVED) {
            return status;
        }
    }
    first_kind = atom_kind;
    first_value = atom_value;
    first_symbol = atom_symbol;
    position = position + atom_used;

    if (first_kind == 0) {
        captured_addend = first_value;
    } else {
        captured_symbol = first_symbol;
        captured_addend = 0;
    }

    if (position < length) {
        operation = text[position];
        if (operation != '+') {
            if (operation != '-') {
                return VALUE_BAD;
            }
        }
        position = position + 1;

        status = parse_atom(text + position, length - position);
        if (status != VALUE_OK) {
            if (status != VALUE_UNRESOLVED) {
                return status;
            }
        }
        second_kind = atom_kind;
        position = position + atom_used;
        if (position != length) {
            return VALUE_BAD;
        }

        if (second_kind == 0) {
            if (operation == '+') {
                captured_addend = (captured_addend + atom_value) & 65535;
            } else {
                captured_addend = (captured_addend - atom_value) & 65535;
            }
        } else {
            if (captured_symbol >= 0) {
                return VALUE_BAD;
            }
            if (operation != '+') {
                return VALUE_BAD;
            }
            captured_symbol = atom_symbol;
        }
    }

    if (captured_symbol >= 0) {
        return VALUE_UNRESOLVED;
    }

    value_result = captured_addend;
    if (captured_prefix != VALUE_PREFIX_NONE) {
        value_result = apply_byte_prefix(captured_addend, captured_prefix);
    }
    return VALUE_OK;
}

/* ---------------- Shared 6502 instruction metadata ---------------- */

int find_mnemonic(char *name, char length)
{
    char candidate;
    char offset;

    if (length != 3) {
        return -1;
    }

    candidate = 0;
    while (candidate < 56) {
        offset = candidate * 3;
        if (upper_char(name[0]) == mnemonic_table[offset]) {
            if (upper_char(name[1]) == mnemonic_table[offset + 1]) {
                if (upper_char(name[2]) == mnemonic_table[offset + 2]) {
                    return candidate;
                }
            }
        }
        candidate = candidate + 1;
    }
    return -1;
}

int find_opcode(char mnemonic, char mode)
{
    int opcode;

    opcode = 0;
    while (opcode < 256) {
        if (opcode_mnemonic[opcode] == mnemonic) {
            if (opcode_mode[opcode] == mode) {
                return opcode;
            }
        }
        opcode = opcode + 1;
    }
    return -1;
}

/* ---------------- Native-style output staging ---------------- */

/* The cursor is authoritative. Convert to a numeric offset only when the
 * exceptional fixup interface needs an offset into the emitted byte buffer.
 * This helper is NOT called for every emitted byte. */
int stage_offset()
{
    return stage_cursor - ass_image;
}


char stage_byte(char value)
{
    if (stage_cursor == ass_image + 11264) {
        return ASSEMBLE_WORK_FULL;
    }
    stage_cursor[0] = value & 255;
    stage_cursor = stage_cursor + 1;
    assembly_pc = (assembly_pc + 1) & 65535;
    return ASSEMBLE_OK;
}

char stage_plain_word_reference(int symbol)
{
    int stage;
    int old_head;
    char status;

    stage = stage_offset();
    old_head = symbol_payload_at(symbol);

    status = stage_byte(old_head & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    status = stage_byte((old_head >> 8) & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }

    symbol_set_payload(symbol, stage + 1);
    return ASSEMBLE_OK;
}

char stage_resolved_instruction(char opcode, char mode, unsigned value)
{
    char width;
    char status;

    width = mode_width[mode];
    if (width == 1) {
        if (value > 255) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
    }

    status = stage_byte(opcode);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    if (width == 0) {
        return ASSEMBLE_OK;
    }

    status = stage_byte(value & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    if (width == 2) {
        return stage_byte((value >> 8) & 255);
    }
    return ASSEMBLE_OK;
}

char stage_resolved_relative(char opcode, unsigned target)
{
    unsigned base;
    int relative;
    char status;

    base = (assembly_pc + 2) & 65535;
    relative = relative_byte(target, base);
    if (relative < 0) {
        return ASSEMBLE_EMIT_ERROR;
    }

    status = stage_byte(opcode);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    return stage_byte(relative);
}

char stage_unresolved_instruction(
    char opcode,
    char mode,
    int symbol,
    unsigned addend,
    char prefix
)
{
    char width;
    int stage;
    char status;
    char kind;

    width = mode_width[mode];
    status = stage_byte(opcode);
    if (status != ASSEMBLE_OK) {
        return status;
    }

    stage = stage_offset();
    if (width == 2) {
        if (prefix == VALUE_PREFIX_NONE) {
            if ((addend & 65535) == 0) {
                return stage_plain_word_reference(symbol);
            }
        }
        status = stage_byte(0);
        if (status != ASSEMBLE_OK) {
            return status;
        }
        status = stage_byte(0);
        if (status != ASSEMBLE_OK) {
            return status;
        }
        return append_fixup(FIXUP_WORD, stage, symbol, addend, prefix);
    }

    if (width != 1) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }

    status = stage_byte(0);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    kind = FIXUP_BYTE;
    if (mode == MODE_RELATIVE) {
        kind = FIXUP_RELATIVE;
    }
    return append_fixup(kind, stage, symbol, addend, prefix);
}

/* ---------------- Instruction parsing and assembly ---------------- */

char short_mode_for_index(char index)
{
    if (index == 1) {
        return MODE_ZERO_PAGE_X;
    }
    if (index == 2) {
        return MODE_ZERO_PAGE_Y;
    }
    return MODE_ZERO_PAGE;
}

char long_mode_for_index(char index)
{
    if (index == 1) {
        return MODE_ABSOLUTE_X;
    }
    if (index == 2) {
        return MODE_ABSOLUTE_Y;
    }
    return MODE_ABSOLUTE;
}

/* ---------------- Native instruction pipeline ---------------- */
/*
 * Like ass/instruction.asm, first classify a zero-copy operand view into its
 * addressing form. No value is parsed, interned, or emitted at this stage.
 * A direct operand deliberately keeps its X/Y suffix and defers width choice
 * until its value is known, just as selectDirectMode does in the ASM version.
 *
 * This is one static workspace, not a C structure or an expression tree.
 * The assembler is nonrecursive and processes one statement at a time.
 */
char instruction_mnemonic;
char instruction_mode;
char instruction_opcode;
char instruction_index;
char instruction_deferred;
char *instruction_text;
char instruction_length;

/* Validate a fixed addressing mode and retain its opcode. */
char instruction_known_mode(char mode)
{
    int opcode;

    opcode = find_opcode(instruction_mnemonic, mode);
    if (opcode < 0) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }
    instruction_mode = mode;
    instruction_opcode = opcode;
    instruction_deferred = 0;
    return ASSEMBLE_OK;
}

/* Only punctuation changes the source view; it is never copied. */
char parse_instruction(char *name, char name_length,
                       char *argument, char argument_length)
{
    int mnemonic;
    int opcode;
    char last;

    mnemonic = find_mnemonic(name, name_length);
    if (mnemonic < 0) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }
    instruction_mnemonic = mnemonic;
    instruction_index = 0;
    instruction_deferred = 0;
    instruction_text = argument;
    instruction_length = argument_length;

    if (argument_length == 0) {
        opcode = find_opcode(instruction_mnemonic, MODE_IMPLIED);
        if (opcode >= 0) {
            return instruction_known_mode(MODE_IMPLIED);
        }
        return instruction_known_mode(MODE_ACCUMULATOR);
    }

    if (argument_length == 1) {
        if (upper_char(argument[0]) == 'A') {
            instruction_length = 0;
            return instruction_known_mode(MODE_ACCUMULATOR);
        }
    }

    if (argument[0] == '#') {
        if (argument_length < 2) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
        instruction_text = argument + 1;
        instruction_length = argument_length - 1;
        return instruction_known_mode(MODE_IMMEDIATE);
    }

    if (argument[0] == '(') {
        if (argument_length < 3) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
        instruction_text = argument + 1;
        last = upper_char(argument[argument_length - 1]);
        if (last == 'Y') {
            if (argument[argument_length - 2] == ',') {
                if (argument_length < 5) {
                    return ASSEMBLE_BAD_INSTRUCTION;
                }
                if (argument[argument_length - 3] != ')') {
                    return ASSEMBLE_BAD_INSTRUCTION;
                }
                instruction_length = argument_length - 4;
                return instruction_known_mode(MODE_INDIRECT_Y);
            }
        }
        if (argument[argument_length - 1] != ')') {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
        if (upper_char(argument[argument_length - 2]) == 'X') {
            if (argument_length < 5) {
                return ASSEMBLE_BAD_INSTRUCTION;
            }
            if (argument[argument_length - 3] != ',') {
                return ASSEMBLE_BAD_INSTRUCTION;
            }
            instruction_length = argument_length - 4;
            return instruction_known_mode(MODE_INDIRECT_X);
        }
        instruction_length = argument_length - 2;
        return instruction_known_mode(MODE_INDIRECT);
    }

    /* Direct operands are dispatched only after value evaluation. */
    if (argument_length >= 3) {
        if (argument[argument_length - 2] == ',') {
            last = upper_char(argument[argument_length - 1]);
            if (last == 'X') {
                instruction_index = 1;
                instruction_length = argument_length - 2;
            } else {
                if (last == 'Y') {
                    instruction_index = 2;
                    instruction_length = argument_length - 2;
                }
            }
        }
    }
    instruction_deferred = 1;
    return ASSEMBLE_OK;
}

/* Choose a direct machine addressing mode, using the decoded value. */
char select_instruction_mode(char value_status)
{
    char short_mode;
    char long_mode;
    int short_opcode;
    int long_opcode;

    if (instruction_index == 0) {
        if (find_opcode(instruction_mnemonic, MODE_RELATIVE) >= 0) {
            return instruction_known_mode(MODE_RELATIVE);
        }
    }

    short_mode = short_mode_for_index(instruction_index);
    long_mode = long_mode_for_index(instruction_index);
    short_opcode = find_opcode(instruction_mnemonic, short_mode);
    long_opcode = find_opcode(instruction_mnemonic, long_mode);

    if (value_status == VALUE_OK) {
        if (value_result <= 255) {
            if (short_opcode >= 0) {
                return instruction_known_mode(short_mode);
            }
        }
        return instruction_known_mode(long_mode);
    }

    /* For unresolved names, there can be no automatic zero-page relaxation.
     * An explicit < or > selects a byte; otherwise use the long mode if it
     * exists, falling back to the sole available short form. */
    if (captured_prefix != VALUE_PREFIX_NONE) {
        return instruction_known_mode(short_mode);
    }
    if (long_opcode >= 0) {
        return instruction_known_mode(long_mode);
    }
    return instruction_known_mode(short_mode);
}

/* One straightforward instruction path: decode syntax, evaluate once, emit. */
char assemble_instruction(char *name, char name_length,
                          char *argument, char argument_length)
{
    char status;
    char value_status;

    status = parse_instruction(name, name_length, argument, argument_length);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    if (instruction_length == 0) {
        if (instruction_deferred != 0) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
        return stage_resolved_instruction(instruction_opcode, instruction_mode, 0);
    }

    value_status = parse_value(instruction_text, instruction_length);
    if (value_status != VALUE_OK) {
        if (value_status != VALUE_UNRESOLVED) {
            if (value_status == VALUE_SYMBOL_FULL) {
                return ASSEMBLE_SYMBOL_FULL;
            }
            if (value_status == VALUE_SCOPE_ERROR) {
                return ASSEMBLE_SCOPE_ERROR;
            }
            return ASSEMBLE_BAD_INSTRUCTION;
        }
    }

    if (instruction_deferred != 0) {
        status = select_instruction_mode(value_status);
        if (status != ASSEMBLE_OK) {
            return status;
        }
    }

    if (value_status == VALUE_UNRESOLVED) {
        return stage_unresolved_instruction(instruction_opcode,
            instruction_mode, captured_symbol, captured_addend,
            captured_prefix);
    }
    if (instruction_mode == MODE_RELATIVE) {
        return stage_resolved_relative(instruction_opcode, value_result);
    }
    return stage_resolved_instruction(instruction_opcode,
        instruction_mode, value_result);
}

/* ---------------- Data declarations ---------------- */

char stage_data_value(char *text, char length, char width)
{
    char status;
    int stage;
    char kind;

    status = parse_value(text, length);
    if (status == VALUE_OK) {
        if (width == 1) {
            if (value_result > 255) {
                return ASSEMBLE_BAD_DATA;
            }
            return stage_byte(value_result);
        }
        status = stage_byte(value_result & 255);
        if (status != ASSEMBLE_OK) {
            return status;
        }
        return stage_byte((value_result >> 8) & 255);
    }

    if (status == VALUE_UNRESOLVED) {
        if (width == 2) {
            if (captured_prefix == VALUE_PREFIX_NONE) {
                if ((captured_addend & 65535) == 0) {
                    return stage_plain_word_reference(captured_symbol);
                }
            }
        }

        stage = stage_offset();
        status = stage_byte(0);
        if (status != ASSEMBLE_OK) {
            return status;
        }
        if (width == 2) {
            status = stage_byte(0);
            if (status != ASSEMBLE_OK) {
                return status;
            }
            kind = FIXUP_WORD;
        } else {
            kind = FIXUP_DATA_BYTE;
        }
        return append_fixup(
            kind,
            stage,
            captured_symbol,
            captured_addend,
            captured_prefix
        );
    }

    if (status == VALUE_SYMBOL_FULL) {
        return ASSEMBLE_SYMBOL_FULL;
    }
    if (status == VALUE_SCOPE_ERROR) {
        return ASSEMBLE_SCOPE_ERROR;
    }
    return ASSEMBLE_BAD_DATA;
}

char assemble_data_list(char *argument, char length, char width)
{
    char cursor;
    char item_start;
    char item_end;
    char status;
    char c;

    cursor = 0;
    while (cursor < length) {
        while (cursor < length) {
            c = argument[cursor];
            if (c == ' ') {
                cursor = cursor + 1;
            } else {
                if (c == 9) {
                    cursor = cursor + 1;
                } else {
                    break;
                }
            }
        }
        if (cursor >= length) {
            return ASSEMBLE_BAD_DATA;
        }

        item_start = cursor;
        item_end = cursor;
        while (cursor < length) {
            c = argument[cursor];
            if (c == ',') {
                break;
            }
            if (c != ' ') {
                if (c != 9) {
                    item_end = cursor + 1;
                }
            }
            cursor = cursor + 1;
        }

        if (item_end == item_start) {
            return ASSEMBLE_BAD_DATA;
        }

        status = stage_data_value(
            argument + item_start,
            item_end - item_start,
            width
        );
        if (status != ASSEMBLE_OK) {
            return status;
        }

        if (cursor >= length) {
            return ASSEMBLE_OK;
        }

        cursor = cursor + 1;
        if (cursor >= length) {
            return ASSEMBLE_BAD_DATA;
        }
    }

    return ASSEMBLE_OK;
}

char assemble_string(char *argument, char length)
{
    char i;
    char status;

    if (length < 2) {
        return ASSEMBLE_BAD_DATA;
    }
    if (argument[0] != '"') {
        return ASSEMBLE_BAD_DATA;
    }
    if (argument[length - 1] != '"') {
        return ASSEMBLE_BAD_DATA;
    }

    i = 1;
    while (i < length - 1) {
        status = stage_byte(argument[i]);
        if (status != ASSEMBLE_OK) {
            return status;
        }
        i = i + 1;
    }
    return stage_byte(0);
}

/* ---------------- Native-style source traversal ---------------- */

/*
 * Source files remain open on one small stack. EOF is owned by its file:
 * the final unterminated line must be processed before closing that file,
 * and an include on that line may temporarily push another input.
 *
 * An io_read result of -1 means the host/C64 adapter has reached EOF;
 * other negative results are I/O errors. This is deliberately not a KERNAL
 * READST emulator: the native C64 adapter owns CHKIN, READST and EOI.
 */
char *source_open_name;
char source_open_length;

/*
 * Construct an include filename only if a directory prefix or ../ handling
 * requires one. With no prefix, the filename is a view of the source line.
 * This follows prepareIncludeName's ownership without copying common names.
 */
char prepare_include_name(char *argument, char length)
{
    char start;
    char count;
    char prefix;
    char output;
    char i;

    if (length < 3) {
        return ASSEMBLE_BAD_STATEMENT;
    }
    if (argument[0] != '"') {
        return ASSEMBLE_BAD_STATEMENT;
    }
    if (argument[length - 1] != '"') {
        return ASSEMBLE_BAD_STATEMENT;
    }

    start = 1;
    count = length - 2;
    prefix = source_directory_length;

    if (count >= 3) {
        if (argument[1] == '.') {
            if (argument[2] == '.') {
                if (argument[3] == '/') {
                    start = 4;
                    count = count - 3;
                    prefix = 0;
                }
            }
        }
    }

    if (prefix + (int)count > 255) {
        return ASSEMBLE_BAD_STATEMENT;
    }

    if (prefix == 0) {
        if (start == 1) {
            source_open_name = argument + 1;
            source_open_length = count;
            return ASSEMBLE_OK;
        }
    }

    output = 0;
    i = 0;
    while (i < prefix) {
        source_path[output] = source_directory[i];
        output = output + 1;
        i = i + 1;
    }
    i = 0;
    while (i < count) {
        source_path[output] = argument[start + i];
        output = output + 1;
        i = i + 1;
    }

    source_open_name = source_path;
    source_open_length = output;
    return ASSEMBLE_OK;
}

char open_root_source(char *name, char length)
{
    int handle;

    handle = io_open(name, length);
    if (handle < 0) {
        return ASSEMBLE_IO_ERROR;
    }
    source_depth = 0;
    source_handle[0] = handle;
    source_eof_pending[0] = 0;
    return ASSEMBLE_OK;
}

char open_include(char *argument, char length)
{
    int handle;
    char status;

    if (source_depth >= 4) {
        return ASSEMBLE_INCLUDE_DEPTH;
    }

    status = prepare_include_name(argument, length);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    handle = io_open(source_open_name, source_open_length);
    if (handle < 0) {
        return ASSEMBLE_IO_ERROR;
    }

    source_depth = source_depth + 1;
    source_handle[source_depth] = handle;
    source_eof_pending[source_depth] = 0;
    return ASSEMBLE_OK;
}

/* Close just the current source, revealing its already-positioned parent. */
char finish_source_file()
{
    io_close(source_handle[source_depth]);
    source_depth = source_depth - 1;
    return ASSEMBLE_OK;
}

/*
 * One call returns one logical line (1), the end of the root file (0),
 * an input error (-1), or a full-line overflow (-2).
 * Child EOF is handled here, not by the statement-processing driver.
 */
int read_source_line()
{
    int c;
    char handle;

    while (source_depth >= 0) {
        if (source_eof_pending[source_depth] != 0) {
            source_eof_pending[source_depth] = 0;
            finish_source_file();
        } else {
            source_line_length = 0;
            handle = source_handle[source_depth];

            while (1) {
                c = io_read(handle);
                if (c < 0) {
                    if (c != -1) {
                        return -1;
                    }
                    source_eof_pending[source_depth] = 1;
                    if (source_line_length != 0) {
                        source_line[source_line_length] = 0;
                        return 1;
                    }
                    break;
                }

                if (c == 13) {
                    source_line[source_line_length] = 0;
                    return 1;
                }
                if (c == 10) {
                    source_line[source_line_length] = 0;
                    return 1;
                }

                if (source_line_length >= 255) {
                    return -2;
                }
                source_line[source_line_length] = c;
                source_line_length = source_line_length + 1;
            }
        }
    }
    return 0;
}

char close_source_tree()
{
    while (source_depth >= 0) {
        finish_source_file();
    }
    return ASSEMBLE_OK;
}

/* ---------------- Statement recognition ---------------- */

int scan_argument(char start)
{
    char i;
    char quote;
    char last;
    char c;

    i = start;
    quote = 0;
    last = start;

    while (i < source_line_length) {
        c = source_line[i];

        if (c == ';') {
            if (quote == 0) {
                i = source_line_length;
            } else {
                last = i + 1;
                i = i + 1;
            }
        } else {
            if (c == 39) {
                if (quote == 0) {
                    quote = 39;
                } else {
                    if (quote == 39) {
                        quote = 0;
                    }
                }
                last = i + 1;
            } else {
                if (c == '"') {
                    if (quote == 0) {
                        quote = '"';
                    } else {
                        if (quote == '"') {
                            quote = 0;
                        }
                    }
                    last = i + 1;
                } else {
                    if (c != ' ') {
                        if (c != 9) {
                            last = i + 1;
                        }
                    }
                }
            }
            i = i + 1;
        }
    }

    return last - start;
}


/*
 * Like ass/parser.asm, source text stays in the caller-owned line buffer.
 * A statement is a transient pair of pointer/length views. Only a label
 * leaves the rest of its line for another call to next_statement.
 *
 * Statement types: 0 end of line, 1 label, 2 assignment, 3 instruction/data.
 */
char source_cursor;
char *statement_name;
char statement_name_length;
char *statement_argument;
char statement_argument_length;

char skip_source_space(char cursor)
{
    while (cursor < source_line_length) {
        if (source_line[cursor] == ' ') {
            cursor = cursor + 1;
        } else {
            if (source_line[cursor] == 9) {
                cursor = cursor + 1;
            } else {
                break;
            }
        }
    }
    return cursor;
}

/* Scan one statement and leave names/arguments as views into source_line. */
char next_statement()
{
    char start;

    source_cursor = skip_source_space(source_cursor);
    if (source_cursor >= source_line_length) {
        return 0;
    }
    if (source_line[source_cursor] == ';') {
        return 0;
    }

    start = source_cursor;
    while (source_cursor < source_line_length) {
        if (source_line[source_cursor] == ' ') {
            break;
        }
        if (source_line[source_cursor] == 9) {
            break;
        }
        source_cursor = source_cursor + 1;
    }

    statement_name = source_line + start;
    statement_name_length = source_cursor - start;

    if (statement_name[statement_name_length - 1] == ':') {
        statement_name_length = statement_name_length - 1;
        return 1;
    }

    source_cursor = skip_source_space(source_cursor);
    if (source_cursor < source_line_length) {
        if (source_line[source_cursor] == '=') {
            source_cursor = skip_source_space(source_cursor + 1);
            statement_argument = source_line + source_cursor;
            statement_argument_length = scan_argument(source_cursor);
            source_cursor = source_line_length;
            return 2;
        }
    }

    statement_argument = source_line + source_cursor;
    statement_argument_length = scan_argument(source_cursor);
    source_cursor = source_line_length;
    return 3;
}

char process_label(char *name, char length)
{
    char status;
    unsigned value;

    if (length == 0) {
        return ASSEMBLE_BAD_STATEMENT;
    }

    if (name[0] == '.') {
        if (current_scope == 0) {
            return ASSEMBLE_SCOPE_ERROR;
        }
    } else {
        if (current_scope == 255) {
            return ASSEMBLE_SCOPE_ERROR;
        }
        status = rewind_local_symbols();
        if (status != ASSEMBLE_OK) {
            return status;
        }
        current_scope = current_scope + 1;
    }

    origin_allowed = 0;
    value = assembly_pc;
    status = define_label(name, length, value);
    return status;
}

char process_symbol(char *name, char name_length, char *argument, char argument_length)
{
    char status;

    if (name_length == 1) {
        if (name[0] == '*') {
            if (origin_allowed == 0) {
                return ASSEMBLE_BAD_ORIGIN;
            }
            status = parse_value(argument, argument_length);
            if (status != VALUE_OK) {
                return ASSEMBLE_BAD_ORIGIN;
            }
            ass_origin = value_result;
            assembly_pc = value_result;
            origin_allowed = 0;
            return ASSEMBLE_OK;
        }
    }

    status = parse_value(argument, argument_length);
    if (status != VALUE_OK) {
        if (status == VALUE_SYMBOL_FULL) {
            return ASSEMBLE_SYMBOL_FULL;
        }
        if (status == VALUE_SCOPE_ERROR) {
            return ASSEMBLE_SCOPE_ERROR;
        }
        return ASSEMBLE_BAD_SYMBOL;
    }
    return define_constant(name, name_length, value_result);
}

char process_instruction_like(
    char *name,
    char name_length,
    char *argument,
    char argument_length
)
{
    if (same_text(name, name_length, "include", 7) != 0) {
        return open_include(argument, argument_length);
    }

    origin_allowed = 0;

    if (same_text(name, name_length, "byte", 4) != 0) {
        return assemble_data_list(argument, argument_length, 1);
    }
    if (same_text(name, name_length, "word", 4) != 0) {
        return assemble_data_list(argument, argument_length, 2);
    }
    if (same_text(name, name_length, "string", 6) != 0) {
        return assemble_string(argument, argument_length);
    }

    return assemble_instruction(name, name_length, argument, argument_length);
}

/* Parse the line once, dispatching each label before any trailing statement. */
char process_source_line()
{
    char kind;
    char status;

    source_cursor = 0;
    while (1) {
        kind = next_statement();
        if (kind == 0) {
            return ASSEMBLE_OK;
        }
        if (kind == 1) {
            status = process_label(statement_name, statement_name_length);
        } else {
            if (kind == 2) {
                if (statement_argument_length == 0) {
                    return ASSEMBLE_BAD_SYMBOL;
                }
                status = process_symbol(
                    statement_name, statement_name_length,
                    statement_argument, statement_argument_length
                );
            } else {
                status = process_instruction_like(
                    statement_name, statement_name_length,
                    statement_argument, statement_argument_length
                );
            }
        }
        if (status != ASSEMBLE_OK) {
            return status;
        }
    }
}

/* ---------------- Whole assembly ---------------- */

char reset_assembler(unsigned default_origin, char *directory, char directory_length)
{
    ass_image_length = 0;
    stage_cursor = ass_image;
    ass_origin = default_origin & 65535;
    assembly_pc = ass_origin;
    source_depth = -1;
    source_directory = directory;
    source_directory_length = directory_length;
    symbol_count = 0;
    symbol_global_end = 0;
    symbol_local_start = 15616;
    symbol_local_count = 0;
    current_scope = 0;
    fixup_end = 0;
    origin_allowed = 1;
    return ASSEMBLE_OK;
}

char all_symbols_defined()
{
    int position;

    position = 0;
    while (position < symbol_global_end) {
        if (symbol_kind_at(position) == SYMBOL_LABEL_UNDEFINED) {
            return 0;
        }
        position = position + 4 + symbol_records[position];
    }
    return all_local_labels_defined();
}

char all_fixups_resolved()
{
    int position;
    position = 0;
    while (position < fixup_end) {
        if (fixup_records[position] != FIXUP_NONE) {
            return 0;
        }
        position = position + 8;
    }
    return 1;
}

char ass_assemble_core(
    char *root_name,
    char root_name_length,
    char *directory,
    char directory_length,
    unsigned default_origin
)
{
    int line_status;
    char status;

    reset_assembler(default_origin, directory, directory_length);
    status = open_root_source(root_name, root_name_length);
    if (status != ASSEMBLE_OK) {
        return status;
    }

    while (1) {
        line_status = read_source_line();
        if (line_status == 0) {
            break;
        }
        if (line_status != 1) {
            close_source_tree();
            if (line_status == -2) {
                return ASSEMBLE_LINE_TOO_LONG;
            }
            return ASSEMBLE_IO_ERROR;
        }

        status = process_source_line();
        if (status != ASSEMBLE_OK) {
            close_source_tree();
            return status;
        }
    }

    if (all_symbols_defined() == 0) {
        return ASSEMBLE_UNDEFINED;
    }
    if (all_fixups_resolved() == 0) {
        return ASSEMBLE_UNDEFINED;
    }

    return ASSEMBLE_OK;
}

/* The original public API exposes an output length to the host adapter.
 * The native streaming implementation itself never maintains that count. */
char ass_assemble(
    char *root_name,
    char root_name_length,
    char *directory,
    char directory_length,
    unsigned default_origin
)
{
    char status;
    status = ass_assemble_core(
        root_name, root_name_length, directory, directory_length, default_origin
    );
    ass_image_length = stage_offset();
    return status;
}
