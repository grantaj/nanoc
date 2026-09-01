/*
 * Candidate Nano C Phase 1 assembler.
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

/*
 * Fixed Phase 1 workspace splits.  With 16-bit Nano C int/unsigned values
 * these consume the same budgets as the native assembler:
 *
 *   staging: 11264 bytes + 640 eight-byte fixups = 16384 bytes
 *   symbols: 896 seven-byte records + 9344 name bytes = 15616 bytes
 *
 * Native ass uses a 12288-byte main symbol workspace plus its fixed 3328-byte
 * persistent continuation at $3300-$3fff.  The C candidate uses the same total
 * target budget as flat arrays, which keeps the representation simple without
 * giving the host implementation extra target memory.
 */
char ass_image[11264];
int ass_image_length;
unsigned ass_origin;

char source_line[256];
int source_line_length;
char source_path[256];
int source_handle[5];
int source_depth;
char *source_directory;
int source_directory_length;

int symbol_name_offset[896];
char symbol_name_length[896];
unsigned symbol_payload[896];
char symbol_scope[896];
char symbol_kind[896];
char symbol_name_bytes[9344];
int symbol_count;
int symbol_name_used;
int current_scope;

char fixup_kind[640];
int fixup_stage[640];
int fixup_symbol[640];
unsigned fixup_addend[640];
char fixup_prefix[640];
int fixup_count;

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
int atom_used;
char atom_kind;

/* Fixup kinds. */
char FIXUP_NONE = 0;
char FIXUP_BYTE = 1;
char FIXUP_WORD = 2;
char FIXUP_RELATIVE = 3;
char FIXUP_DATA_BYTE = 4;

int origin_allowed;

/* ---------------- Small text/value helpers ---------------- */

int upper_char(int c)
{
    if (c >= 'a') {
        if (c <= 'z') {
            return c - 32;
        }
    }
    return c;
}

int same_text(char *a, int a_length, char *b, int b_length)
{
    int i;

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

int apply_byte_prefix(unsigned value, int prefix)
{
    value = value & 65535;
    if (prefix == VALUE_PREFIX_LOW) {
        return value & 255;
    }
    return (value >> 8) & 255;
}

int hex_nibble(int c)
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

int append_fixup(int kind, int stage, int symbol, unsigned addend, int prefix)
{
    int n;

    n = fixup_count;
    if (n >= 640) {
        return ASSEMBLE_WORK_FULL;
    }

    fixup_kind[n] = kind;
    fixup_stage[n] = stage;
    fixup_symbol[n] = symbol;
    fixup_addend[n] = addend & 65535;
    fixup_prefix[n] = prefix;
    fixup_count = n + 1;
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

int trim_fixups()
{
    while (fixup_count > 0) {
        if (fixup_kind[fixup_count - 1] != FIXUP_NONE) {
            return ASSEMBLE_OK;
        }
        fixup_count = fixup_count - 1;
    }
    return ASSEMBLE_OK;
}

int resolve_fixups_for_symbol(int symbol)
{
    int i;
    int kind;
    unsigned value;
    int stage;
    int relative;

    i = 0;
    while (i < fixup_count) {
        kind = fixup_kind[i];
        if (kind != FIXUP_NONE) {
            if (fixup_symbol[i] == symbol) {
                value = (symbol_payload[symbol] + fixup_addend[i]) & 65535;
                if (fixup_prefix[i] != VALUE_PREFIX_NONE) {
                    value = apply_byte_prefix(value, fixup_prefix[i]);
                }
                stage = fixup_stage[i];

                if (kind == FIXUP_WORD) {
                    ass_image[stage] = value & 255;
                    ass_image[stage + 1] = (value >> 8) & 255;
                } else {
                    if (kind == FIXUP_RELATIVE) {
                        relative = relative_byte(
                            value,
                            (ass_origin + stage + 1) & 65535
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
                fixup_kind[i] = FIXUP_NONE;
            }
        }
        i = i + 1;
    }
    return trim_fixups();
}

/* ---------------- Linear owned-name symbol table ---------------- */

int scope_for_name(char *name, int length)
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

int find_symbol(char *name, int length)
{
    int wanted_scope;
    int i;
    int j;
    int offset;
    int same;

    wanted_scope = scope_for_name(name, length);
    if (wanted_scope < 0) {
        return -2;
    }

    i = 0;
    while (i < symbol_count) {
        if (symbol_scope[i] == wanted_scope) {
            if (symbol_name_length[i] == length) {
                offset = symbol_name_offset[i];
                same = 1;
                j = 0;
                while (j < length) {
                    if (symbol_name_bytes[offset + j] != name[j]) {
                        same = 0;
                    }
                    j = j + 1;
                }
                if (same != 0) {
                    return i;
                }
            }
        }
        i = i + 1;
    }
    return -1;
}

int allocate_symbol(char *name, int length, int kind, unsigned payload)
{
    int scope;
    int n;
    int i;

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

    n = symbol_count;
    symbol_name_offset[n] = symbol_name_used;
    symbol_name_length[n] = length;
    symbol_payload[n] = payload & 65535;
    symbol_scope[n] = scope;
    symbol_kind[n] = kind;

    i = 0;
    while (i < length) {
        symbol_name_bytes[symbol_name_used + i] = name[i];
        i = i + 1;
    }

    symbol_name_used = symbol_name_used + length;
    symbol_count = n + 1;
    return n;
}

int intern_label(char *name, int length)
{
    int symbol;

    symbol = find_symbol(name, length);
    if (symbol >= 0) {
        if (symbol_kind[symbol] == SYMBOL_CONSTANT) {
            return -4;
        }
        return symbol;
    }
    if (symbol == -2) {
        return -2;
    }
    return allocate_symbol(name, length, SYMBOL_LABEL_UNDEFINED, 0);
}

int define_constant(char *name, int length, unsigned value)
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

int patch_word_chain(int head, unsigned value)
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

int define_label(char *name, int length, unsigned value)
{
    int symbol;
    int old_head;
    int status;

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

    if (symbol_kind[symbol] != SYMBOL_LABEL_UNDEFINED) {
        return ASSEMBLE_BAD_SYMBOL;
    }

    old_head = symbol_payload[symbol];
    symbol_payload[symbol] = value & 65535;
    symbol_kind[symbol] = SYMBOL_LABEL_DEFINED;

    status = patch_word_chain(old_head, value);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    return resolve_fixups_for_symbol(symbol);
}

/* ---------------- Tiny assembler value grammar ---------------- */

int parse_atom(char *text, int length)
{
    int i;
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

    if (symbol_kind[symbol] == SYMBOL_LABEL_UNDEFINED) {
        atom_symbol = symbol;
        atom_kind = 1;
        return VALUE_UNRESOLVED;
    }

    atom_value = symbol_payload[symbol];
    atom_kind = 0;
    return VALUE_OK;
}

int parse_value(char *text, int length)
{
    int position;
    int status;
    int first_kind;
    unsigned first_value;
    int first_symbol;
    int operation;
    int second_kind;

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

int find_mnemonic(char *name, int length)
{
    int candidate;
    int offset;

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

int find_opcode(int mnemonic, int mode)
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

/* ---------------- Final-size staging ---------------- */

int stage_byte(int value)
{
    if (ass_image_length >= 11264) {
        return ASSEMBLE_WORK_FULL;
    }
    ass_image[ass_image_length] = value & 255;
    ass_image_length = ass_image_length + 1;
    return ASSEMBLE_OK;
}

int stage_plain_word_reference(int symbol)
{
    int stage;
    int old_head;
    int status;

    stage = ass_image_length;
    old_head = symbol_payload[symbol];

    status = stage_byte(old_head & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }
    status = stage_byte((old_head >> 8) & 255);
    if (status != ASSEMBLE_OK) {
        return status;
    }

    symbol_payload[symbol] = stage + 1;
    return ASSEMBLE_OK;
}

int stage_resolved_instruction(int opcode, int mode, unsigned value)
{
    int width;
    int status;

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

int stage_resolved_relative(int opcode, unsigned target)
{
    unsigned base;
    int relative;
    int status;

    base = (ass_origin + ass_image_length + 2) & 65535;
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

int stage_unresolved_instruction(
    int opcode,
    int mode,
    int symbol,
    unsigned addend,
    int prefix
)
{
    int width;
    int stage;
    int status;
    int kind;

    width = mode_width[mode];
    status = stage_byte(opcode);
    if (status != ASSEMBLE_OK) {
        return status;
    }

    stage = ass_image_length;
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

int short_mode_for_index(int index)
{
    if (index == 1) {
        return MODE_ZERO_PAGE_X;
    }
    if (index == 2) {
        return MODE_ZERO_PAGE_Y;
    }
    return MODE_ZERO_PAGE;
}

int long_mode_for_index(int index)
{
    if (index == 1) {
        return MODE_ABSOLUTE_X;
    }
    if (index == 2) {
        return MODE_ABSOLUTE_Y;
    }
    return MODE_ABSOLUTE;
}

int assemble_mode_value(int mnemonic, int mode, char *text, int length)
{
    int opcode;
    int status;

    opcode = find_opcode(mnemonic, mode);
    if (opcode < 0) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }

    status = parse_value(text, length);
    if (status == VALUE_OK) {
        if (mode == MODE_RELATIVE) {
            return stage_resolved_relative(opcode, value_result);
        }
        return stage_resolved_instruction(opcode, mode, value_result);
    }
    if (status == VALUE_UNRESOLVED) {
        return stage_unresolved_instruction(
            opcode,
            mode,
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
    return ASSEMBLE_BAD_INSTRUCTION;
}

int assemble_direct_value(int mnemonic, char *text, int length, int index)
{
    int status;
    int short_mode;
    int long_mode;
    int short_opcode;
    int long_opcode;
    int mode;
    int opcode;

    if (index == 0) {
        opcode = find_opcode(mnemonic, MODE_RELATIVE);
        if (opcode >= 0) {
            return assemble_mode_value(mnemonic, MODE_RELATIVE, text, length);
        }
    }

    status = parse_value(text, length);
    if (status != VALUE_OK) {
        if (status != VALUE_UNRESOLVED) {
            if (status == VALUE_SYMBOL_FULL) {
                return ASSEMBLE_SYMBOL_FULL;
            }
            if (status == VALUE_SCOPE_ERROR) {
                return ASSEMBLE_SCOPE_ERROR;
            }
            return ASSEMBLE_BAD_INSTRUCTION;
        }
    }

    short_mode = short_mode_for_index(index);
    long_mode = long_mode_for_index(index);
    short_opcode = find_opcode(mnemonic, short_mode);
    long_opcode = find_opcode(mnemonic, long_mode);

    if (status == VALUE_OK) {
        if (value_result <= 255) {
            if (short_opcode >= 0) {
                return stage_resolved_instruction(short_opcode, short_mode, value_result);
            }
        }
        if (long_opcode >= 0) {
            return stage_resolved_instruction(long_opcode, long_mode, value_result);
        }
        return ASSEMBLE_BAD_INSTRUCTION;
    }

    mode = long_mode;
    opcode = long_opcode;

    if (captured_prefix != VALUE_PREFIX_NONE) {
        mode = short_mode;
        opcode = short_opcode;
    } else {
        if (long_opcode < 0) {
            mode = short_mode;
            opcode = short_opcode;
        }
    }

    if (opcode < 0) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }
    return stage_unresolved_instruction(
        opcode,
        mode,
        captured_symbol,
        captured_addend,
        captured_prefix
    );
}

int assemble_instruction(char *name, int name_length, char *argument, int argument_length)
{
    int mnemonic;
    int opcode;
    int index;
    int core_length;

    mnemonic = find_mnemonic(name, name_length);
    if (mnemonic < 0) {
        return ASSEMBLE_BAD_INSTRUCTION;
    }

    if (argument_length == 0) {
        opcode = find_opcode(mnemonic, MODE_IMPLIED);
        if (opcode >= 0) {
            return stage_resolved_instruction(opcode, MODE_IMPLIED, 0);
        }
        opcode = find_opcode(mnemonic, MODE_ACCUMULATOR);
        if (opcode >= 0) {
            return stage_resolved_instruction(opcode, MODE_ACCUMULATOR, 0);
        }
        return ASSEMBLE_BAD_INSTRUCTION;
    }

    if (argument_length == 1) {
        if (upper_char(argument[0]) == 'A') {
            opcode = find_opcode(mnemonic, MODE_ACCUMULATOR);
            if (opcode < 0) {
                return ASSEMBLE_BAD_INSTRUCTION;
            }
            return stage_resolved_instruction(opcode, MODE_ACCUMULATOR, 0);
        }
    }

    if (argument[0] == '#') {
        if (argument_length < 2) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }
        return assemble_mode_value(
            mnemonic,
            MODE_IMMEDIATE,
            argument + 1,
            argument_length - 1
        );
    }

    if (argument[0] == '(') {
        if (argument_length < 3) {
            return ASSEMBLE_BAD_INSTRUCTION;
        }

        if (upper_char(argument[argument_length - 1]) == 'Y') {
            if (argument[argument_length - 2] == ',') {
                if (argument[argument_length - 3] != ')') {
                    return ASSEMBLE_BAD_INSTRUCTION;
                }
                core_length = argument_length - 4;
                if (core_length <= 0) {
                    return ASSEMBLE_BAD_INSTRUCTION;
                }
                return assemble_mode_value(
                    mnemonic,
                    MODE_INDIRECT_Y,
                    argument + 1,
                    core_length
                );
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
            core_length = argument_length - 4;
            return assemble_mode_value(
                mnemonic,
                MODE_INDIRECT_X,
                argument + 1,
                core_length
            );
        }

        core_length = argument_length - 2;
        return assemble_mode_value(
            mnemonic,
            MODE_INDIRECT,
            argument + 1,
            core_length
        );
    }

    index = 0;
    core_length = argument_length;
    if (argument_length >= 3) {
        if (argument[argument_length - 2] == ',') {
            if (upper_char(argument[argument_length - 1]) == 'X') {
                index = 1;
                core_length = argument_length - 2;
            } else {
                if (upper_char(argument[argument_length - 1]) == 'Y') {
                    index = 2;
                    core_length = argument_length - 2;
                }
            }
        }
    }

    return assemble_direct_value(mnemonic, argument, core_length, index);
}

/* ---------------- Data declarations ---------------- */

int stage_data_value(char *text, int length, int width)
{
    int status;
    int stage;
    int kind;

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

        stage = ass_image_length;
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

int assemble_data_list(char *argument, int length, int width)
{
    int cursor;
    int item_start;
    int item_end;
    int status;
    int c;

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

int assemble_string(char *argument, int length)
{
    int i;
    int status;

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

/* ---------------- Source traversal ---------------- */

int open_include(char *argument, int length)
{
    int input_start;
    int input_length;
    int output;
    int i;
    int parent_path;
    int handle;

    if (length < 3) {
        return ASSEMBLE_BAD_STATEMENT;
    }
    if (argument[0] != '"') {
        return ASSEMBLE_BAD_STATEMENT;
    }
    if (argument[length - 1] != '"') {
        return ASSEMBLE_BAD_STATEMENT;
    }
    if (source_depth >= 4) {
        return ASSEMBLE_INCLUDE_DEPTH;
    }

    input_start = 1;
    input_length = length - 2;
    output = 0;
    parent_path = 0;

    if (input_length >= 3) {
        if (argument[input_start] == '.') {
            if (argument[input_start + 1] == '.') {
                if (argument[input_start + 2] == '/') {
                    parent_path = 1;
                    input_start = input_start + 3;
                    input_length = input_length - 3;
                }
            }
        }
    }

    if (parent_path == 0) {
        i = 0;
        while (i < source_directory_length) {
            source_path[output] = source_directory[i];
            output = output + 1;
            i = i + 1;
        }
    }

    if (output + input_length > 255) {
        return ASSEMBLE_BAD_STATEMENT;
    }

    i = 0;
    while (i < input_length) {
        source_path[output] = argument[input_start + i];
        output = output + 1;
        i = i + 1;
    }

    handle = io_open(source_path, output);
    if (handle < 0) {
        return ASSEMBLE_IO_ERROR;
    }

    source_depth = source_depth + 1;
    source_handle[source_depth] = handle;
    return ASSEMBLE_OK;
}

int read_source_line()
{
    int c;
    int handle;

    source_line_length = 0;
    handle = source_handle[source_depth];

    while (1) {
        c = io_read(handle);
        if (c < 0) {
            if (c == -1) {
                if (source_line_length != 0) {
                    source_line[source_line_length] = 0;
                    return 1;
                }
                return 0;
            }
            return -1;
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

int close_source_tree()
{
    while (source_depth >= 0) {
        io_close(source_handle[source_depth]);
        source_depth = source_depth - 1;
    }
    return ASSEMBLE_OK;
}

/* ---------------- Statement recognition ---------------- */

int scan_argument(int start)
{
    int i;
    int quote;
    int last;
    int c;

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

int process_label(char *name, int length)
{
    int status;
    unsigned value;

    if (length == 0) {
        return ASSEMBLE_BAD_STATEMENT;
    }

    if (name[0] == '.') {
        if (current_scope == 0) {
            return ASSEMBLE_SCOPE_ERROR;
        }
    } else {
        current_scope = current_scope + 1;
        if (current_scope > 255) {
            return ASSEMBLE_SCOPE_ERROR;
        }
    }

    origin_allowed = 0;
    value = (ass_origin + ass_image_length) & 65535;
    status = define_label(name, length, value);
    return status;
}

int process_symbol(char *name, int name_length, char *argument, int argument_length)
{
    int status;

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

int process_instruction_like(
    char *name,
    int name_length,
    char *argument,
    int argument_length
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

int process_source_line()
{
    int cursor;
    int name_start;
    int name_length;
    int argument_start;
    int argument_length;
    int status;

    cursor = 0;

    while (cursor < source_line_length) {
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

        if (cursor >= source_line_length) {
            return ASSEMBLE_OK;
        }
        if (source_line[cursor] == ';') {
            return ASSEMBLE_OK;
        }

        name_start = cursor;
        while (cursor < source_line_length) {
            if (source_line[cursor] == ' ') {
                break;
            }
            if (source_line[cursor] == 9) {
                break;
            }
            cursor = cursor + 1;
        }
        name_length = cursor - name_start;
        if (name_length == 0) {
            return ASSEMBLE_BAD_STATEMENT;
        }

        if (source_line[name_start + name_length - 1] == ':') {
            status = process_label(source_line + name_start, name_length - 1);
            if (status != ASSEMBLE_OK) {
                return status;
            }
            /*
             * A label consumes only its own lexeme.  Continue so
             * "label: word 0" remains one line and two statements.
             */
        } else {
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

            if (cursor < source_line_length) {
                if (source_line[cursor] == '=') {
                    cursor = cursor + 1;
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
                    argument_start = cursor;
                    argument_length = scan_argument(argument_start);
                    if (argument_length == 0) {
                        return ASSEMBLE_BAD_SYMBOL;
                    }
                    return process_symbol(
                        source_line + name_start,
                        name_length,
                        source_line + argument_start,
                        argument_length
                    );
                }
            }

            argument_start = cursor;
            argument_length = scan_argument(argument_start);
            return process_instruction_like(
                source_line + name_start,
                name_length,
                source_line + argument_start,
                argument_length
            );
        }
    }

    return ASSEMBLE_OK;
}

/* ---------------- Whole assembly ---------------- */

int reset_assembler(unsigned default_origin, char *directory, int directory_length)
{
    ass_image_length = 0;
    ass_origin = default_origin & 65535;
    source_depth = -1;
    source_directory = directory;
    source_directory_length = directory_length;
    symbol_count = 0;
    symbol_name_used = 0;
    current_scope = 0;
    fixup_count = 0;
    origin_allowed = 1;
    return ASSEMBLE_OK;
}

int all_symbols_defined()
{
    int i;

    i = 0;
    while (i < symbol_count) {
        if (symbol_kind[i] == SYMBOL_LABEL_UNDEFINED) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

int all_fixups_resolved()
{
    int i;

    i = 0;
    while (i < fixup_count) {
        if (fixup_kind[i] != FIXUP_NONE) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

int ass_assemble(
    char *root_name,
    int root_name_length,
    char *directory,
    int directory_length,
    unsigned default_origin
)
{
    int handle;
    int line_status;
    int status;

    reset_assembler(default_origin, directory, directory_length);

    handle = io_open(root_name, root_name_length);
    if (handle < 0) {
        return ASSEMBLE_IO_ERROR;
    }

    source_depth = 0;
    source_handle[0] = handle;

    while (source_depth >= 0) {
        line_status = read_source_line();

        if (line_status == 1) {
            status = process_source_line();
            if (status != ASSEMBLE_OK) {
                close_source_tree();
                return status;
            }
        } else {
            if (line_status == 0) {
                io_close(source_handle[source_depth]);
                source_depth = source_depth - 1;
            } else {
                close_source_tree();
                if (line_status == -2) {
                    return ASSEMBLE_LINE_TOO_LONG;
                }
                return ASSEMBLE_IO_ERROR;
            }
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
