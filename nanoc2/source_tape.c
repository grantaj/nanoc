/*
 * Small C-source -> typed-operation adapter for nanoc2's replacement emitter.
 * This is a bounded first tranche of the existing Nano C grammar: byte scalar
 * comparisons, byte array/pointer indexes, if/while/break/return, fixed-stride
 * record address expressions. It is NOT a new whole-language compiler yet.
 *
 * There are no named-function templates or machine-code rewrite passes.
 * The eventual nanoc1 integration replaces this scanner with nanoc1's tested
 * scanner/symbol parser. Only ta_operand(), ta_condition(), and ta_action()
 * are semantic lowering logic intended to survive that integration.
 */

/* tb_add, tb_reset, tb_compile, tb_count, tb_a are provided by the C backend. */
char ta_names[768];       /* 24 bindings of 32 bytes */
char ta_kinds[24];        /* 1 scalar, 2 fixed array, 3 byte pointer, 4 record base */
char ta_ids[24];         /* scalar ZP home, array id, or pointer slot */
char ta_bindings;
char ta_token[48];
char ta_tok_type;        /* 1 identifier, 2 integer, 3 punctuation, 0 EOF */
unsigned ta_tok_number;
char *ta_input;
unsigned ta_cursor;
char ta_error;
unsigned ta_label_number;
char ta_frames[20];      /* 1 function, 2 if, 3 while */
unsigned ta_frame_head[20];
unsigned ta_frame_end[20];
char ta_depth;
unsigned ta_single_if;
/* two expression operands, with their address components */
char ta_o_kind[2];       /* 1 scalar, 2 absolute table, 3 indirect table, 4 literal */
char ta_o_id[2];
char ta_o_idx[2];
unsigned ta_o_number[2];
char ta_base_event[24];  /* deferred scaled-address op, 255 if absent */
char ta_rel[3];

char ta_equal(char *a, char *b)
{
    unsigned i;
    i = 0;
    while (a[i] != 0 & b[i] != 0) {
        if (a[i] != b[i]) return 0;
        i = i + 1;
    }
    return a[i] == b[i];
}

char ta_register(char *name, char kind, char id)
{
    unsigned i;
    unsigned slot;
    if (ta_bindings >= 24) return 0;
    slot = ta_bindings;
    i = 0;
    while (name[i] != 0) {
        if (i >= 30) return 0;
        ta_names[slot * 32 + i] = name[i];
        i = i + 1;
    }
    ta_names[slot * 32 + i] = 0;
    ta_kinds[slot] = kind;
    ta_ids[slot] = id;
    ta_base_event[slot] = 255;
    ta_bindings = ta_bindings + 1;
    return 1;
}

int ta_lookup(char *s)
{
    unsigned i;
    i = 0;
    while (i < ta_bindings) {
        if (ta_equal(s, ta_names + i * 32) != 0) return i;
        i = i + 1;
    }
    return -1;
}

char ta_space(char c)
{
    return c == ' ' | c == '\n' | c == '\t' | c == '\r';
}

char ta_letter(char c)
{
    return (c >= 'a' & c <= 'z') | (c >= 'A' & c <= 'Z') | c == '_';
}

char ta_digit(char c)
{
    return c >= '0' & c <= '9';
}

char ta_scan()
{
    unsigned j;
    char c;
    char d;
    while (ta_space(ta_input[ta_cursor])) ta_cursor = ta_cursor + 1;
    /* Ignore C block comments, but do not silently accept // comments. */
    while (ta_input[ta_cursor] == '/' & ta_input[ta_cursor + 1] == '*') {
        ta_cursor = ta_cursor + 2;
        while (ta_input[ta_cursor] != 0) {
            if (ta_input[ta_cursor] == '*' & ta_input[ta_cursor + 1] == '/') break;
            ta_cursor = ta_cursor + 1;
        }
        if (ta_input[ta_cursor] == 0) { ta_error = 1; return 0; }
        ta_cursor = ta_cursor + 2;
        while (ta_space(ta_input[ta_cursor])) ta_cursor = ta_cursor + 1;
    }
    c = ta_input[ta_cursor];
    if (c == 0) { ta_tok_type = 0; ta_token[0] = 0; return 1; }
    j = 0;
    if (ta_letter(c)) {
        ta_tok_type = 1;
        while (ta_letter(ta_input[ta_cursor]) | ta_digit(ta_input[ta_cursor])) {
            if (j >= 46) { ta_error = 2; return 0; }
            ta_token[j] = ta_input[ta_cursor];
            j = j + 1;
            ta_cursor = ta_cursor + 1;
        }
    } else if (ta_digit(c)) {
        ta_tok_type = 2;
        ta_tok_number = 0;
        while (ta_digit(ta_input[ta_cursor])) {
            if (j >= 46) { ta_error = 2; return 0; }
            d = ta_input[ta_cursor];
            ta_tok_number = ta_tok_number * 10 + d - '0';
            ta_token[j] = d;
            j = j + 1;
            ta_cursor = ta_cursor + 1;
        }
    } else {
        ta_tok_type = 3;
        ta_token[j] = c;
        j = j + 1;
        ta_cursor = ta_cursor + 1;
        d = ta_input[ta_cursor];
        if ((c == '!' | c == '=' | c == '<' | c == '>') & d == '=') {
            ta_token[j] = d;
            j = j + 1;
            ta_cursor = ta_cursor + 1;
        }
    }
    ta_token[j] = 0;
    return 1;
}

char ta_is(char *s)
{
    return ta_equal(ta_token, s);
}

char ta_need(char *s)
{
    if (ta_is(s) == 0) { ta_error = 3; return 0; }
    return ta_scan();
}

char ta_add(char op, char dst, char a, char b, unsigned k)
{
    if (tb_add(op,dst,a,b,k) == 0) { ta_error = 4; return 0; }
    return 1;
}

unsigned ta_label()
{
    unsigned result;
    result = ta_label_number;
    ta_label_number = ta_label_number + 1;
    return result;
}

/* Resolve one source operand and its indexed addressing relationship. */
char ta_operand(char which)
{
    int binding;
    int base;
    int index;
    char bk;
    char id;
    if (ta_tok_type == 2) {
        ta_o_kind[which] = 4;
        ta_o_number[which] = ta_tok_number;
        return ta_scan();
    }
    if (ta_tok_type != 1) { ta_error = 5; return 0; }
    binding = ta_lookup(ta_token);
    if (binding < 0) { ta_error = 6; return 0; }
    bk = ta_kinds[binding]; id = ta_ids[binding];
    if (ta_scan() == 0) return 0;
    if (ta_is("[") == 0) {
        if (bk != 1) { ta_error = 7; return 0; }
        ta_o_kind[which] = 1; ta_o_id[which] = id;
        return 1;
    }
    if (bk != 2 & bk != 3) { ta_error = 7; return 0; }
    if (ta_scan() == 0) return 0;
    if (ta_tok_type != 1) { ta_error = 8; return 0; }
    base = ta_lookup(ta_token);
    if (base < 0) { ta_error = 6; return 0; }
    if (ta_scan() == 0) return 0;
    if (ta_is("+")) {
        /* base + index: base is an affine record offset from earlier. */
        if (ta_kinds[base] != 4) { ta_error = 9; return 0; }
        if (ta_scan() == 0) return 0;
        if (ta_tok_type != 1) { ta_error = 9; return 0; }
        index = ta_lookup(ta_token);
        if (index < 0) { ta_error = 6; return 0; }
        if (ta_kinds[index] != 1) { ta_error = 9; return 0; }
        if (ta_base_event[base] == 255) { ta_error = 10; return 0; }
        /* The base array is discovered from this use, not its definition. */
        if (tb_a[ta_base_event[base]] != 0 & tb_a[ta_base_event[base]] != id) {
            ta_error = 11; return 0;
        }
        tb_a[ta_base_event[base]] = id;
        ta_o_kind[which] = 3;
        ta_o_id[which] = ta_ids[base];
        ta_o_idx[which] = ta_ids[index];
        if (ta_scan() == 0) return 0;
    } else {
        if (ta_kinds[base] != 1) { ta_error = 9; return 0; }
        ta_o_kind[which] = bk == 3 ? 3 : 2;
        ta_o_id[which] = id;
        ta_o_idx[which] = ta_ids[base];
    }
    if (ta_need("]") == 0) return 0;
    return 1;
}

char ta_condition(unsigned exit_label)
{
    char relation;
    char k;
    char left;
    char right;
    if (ta_need("(") == 0) return 0;
    if (ta_operand(0) == 0) return 0;
    relation = 0;
    if (ta_is("==")) relation = 2;   /* false when not equal */
    if (ta_is("!=")) relation = 1;   /* false when equal */
    if (ta_is("<")) relation = 4;    /* false when carry set */
    if (ta_is(">=")) relation = 3;   /* false when carry clear */
    if (relation == 0) { ta_error = 12; return 0; }
    if (ta_scan() == 0) return 0;
    if (ta_operand(1) == 0) return 0;
    if (ta_need(")") == 0) return 0;
    left = ta_o_kind[0]; right = ta_o_kind[1];
    if (left == 2 | left == 3) {
        k = left == 2 ? 4 : 6;
        if (ta_add(k,0,ta_o_id[0],ta_o_idx[0],0) == 0) return 0;
        if (right == 2 | right == 3) {
            k = right == 2 ? 5 : 7;
            if (ta_add(k,0,ta_o_id[1],ta_o_idx[1],0) == 0) return 0;
        } else if (right == 1) {
            if (ta_add(18,0,ta_o_id[1],0,0) == 0) return 0;
        } else if (right == 4) {
            if (ta_add(17,0,0,0,ta_o_number[1]) == 0) return 0;
        } else { ta_error = 13; return 0; }
    } else if (left == 1) {
        if (right == 1) {
            if (ta_add(9,ta_o_id[0],ta_o_id[1],0,0) == 0) return 0;
        } else if (right == 4) {
            if (ta_add(8,ta_o_id[0],0,0,ta_o_number[1]) == 0) return 0;
        } else { ta_error = 13; return 0; }
    } else { ta_error = 13; return 0; }
    return ta_add(10,0,relation,0,exit_label);
}

char ta_assignment()
{
    int lhs;
    int rhs;
    unsigned count;
    char kind;
    char id;
    lhs = ta_lookup(ta_token);
    if (lhs < 0) { ta_error = 6; return 0; }
    kind = ta_kinds[lhs]; id = ta_ids[lhs];
    if (ta_scan() == 0) return 0;
    if (ta_need("=") == 0) return 0;
    if (ta_tok_type == 2) {
        if (kind != 1) { ta_error = 14; return 0; }
        if (ta_add(2,id,0,0,ta_tok_number) == 0) return 0;
        if (ta_scan() == 0) return 0;
    } else if (ta_tok_type == 1) {
        rhs = ta_lookup(ta_token);
        if (rhs < 0) { ta_error = 6; return 0; }
        if (ta_kinds[rhs] != 1) { ta_error = 14; return 0; }
        if (ta_scan() == 0) return 0;
        if (kind == 1 & ta_is("+")) {
            if (lhs != rhs) { ta_error = 15; return 0; }
            if (ta_scan() == 0) return 0;
            if (ta_tok_type != 2 | ta_tok_number != 1) { ta_error = 15; return 0; }
            if (ta_add(3,id,0,0,0) == 0) return 0;
            if (ta_scan() == 0) return 0;
        } else if (kind == 4 & ta_is("*")) {
            if (ta_scan() == 0) return 0;
            if (ta_tok_type != 2) { ta_error = 14; return 0; }
            count = tb_count;
            if (count >= 255) { ta_error = 4; return 0; }
            /* Array id will be filled in at first indexed use of this base. */
            if (ta_add(14,id,0,ta_ids[rhs],ta_tok_number) == 0) return 0;
            ta_base_event[lhs] = count;
            if (ta_scan() == 0) return 0;
        } else { ta_error = 15; return 0; }
    } else { ta_error = 14; return 0; }
    return ta_need(";");
}

char ta_start()
{
    ta_cursor = 0;
    ta_error = 0;
    ta_depth = 0;
    ta_single_if = 0;
    ta_label_number = 10;
    tb_reset();
    if (ta_scan() == 0) return 0;
    /* A function signature is typechecked by nanoc1 before this adapter.
     * The temporary adapter starts at the opening brace of its exact body.
     */
    while (ta_tok_type != 0 & ta_is("{") == 0) {
        if (ta_scan() == 0) return 0;
    }
    if (ta_need("{") == 0) return 0;
    ta_frames[0] = 1;
    ta_depth = 1;
    return 1;
}

char ta_compile_source(char *source)
{
    unsigned label;
    unsigned head;
    unsigned end;
    char kind;
    char is_single;
    int symbol;
    ta_input = source;
    if (ta_start() == 0) return 0;
    while (ta_depth != 0 & ta_tok_type != 0) {
        is_single = 0;
        if (ta_single_if != 0) is_single = 1;
        if (ta_is("char") | ta_is("int") | ta_is("unsigned")) {
            if (ta_scan() == 0) return 0;
            if (ta_tok_type != 1) { ta_error = 16; return 0; }
            symbol = ta_lookup(ta_token);
            if (symbol < 0) { ta_error = 6; return 0; }
            if (ta_scan() == 0) return 0;
            if (ta_need(";") == 0) return 0;
        } else if (ta_is("if") | ta_is("while")) {
            kind = ta_is("while") ? 3 : 2;
            if (ta_scan() == 0) return 0;
            head = 0;
            if (kind == 3) {
                head = ta_label();
                if (ta_add(1,0,0,0,head) == 0) return 0;
            }
            end = ta_label();
            if (ta_condition(end) == 0) return 0;
            if (ta_is("{")) {
                if (ta_depth >= 20) { ta_error = 17; return 0; }
                ta_frames[ta_depth] = kind;
                ta_frame_head[ta_depth] = head;
                ta_frame_end[ta_depth] = end;
                ta_depth = ta_depth + 1;
                if (ta_scan() == 0) return 0;
            } else if (kind == 2 & ta_single_if == 0) {
                ta_single_if = end;
            } else { ta_error = 18; return 0; }
            is_single = 0;
        } else if (ta_is("}")) {
            if (ta_depth == 0) { ta_error = 19; return 0; }
            ta_depth = ta_depth - 1;
            kind = ta_frames[ta_depth];
            if (kind == 3) {
                if (ta_add(11,0,0,0,ta_frame_head[ta_depth]) == 0) return 0;
            }
            if (kind != 1) {
                if (ta_add(1,0,0,0,ta_frame_end[ta_depth]) == 0) return 0;
            }
            if (ta_scan() == 0) return 0;
        } else if (ta_is("return")) {
            if (ta_scan() == 0) return 0;
            if (ta_tok_type == 2) {
                if (ta_add(13,0,0,0,ta_tok_number) == 0) return 0;
                if (ta_scan() == 0) return 0;
            } else if (ta_tok_type == 1) {
                symbol = ta_lookup(ta_token);
                if (symbol < 0 | ta_kinds[symbol] != 1) { ta_error = 6; return 0; }
                if (ta_add(12,ta_ids[symbol],0,0,0) == 0) return 0;
                if (ta_scan() == 0) return 0;
            } else { ta_error = 20; return 0; }
            if (ta_need(";") == 0) return 0;
        } else if (ta_is("break")) {
            kind = ta_depth;
            while (kind != 0) {
                kind = kind - 1;
                if (ta_frames[kind] == 3) break;
            }
            if (ta_frames[kind] != 3) { ta_error = 21; return 0; }
            if (ta_add(11,0,0,0,ta_frame_end[kind]) == 0) return 0;
            if (ta_scan() == 0) return 0;
            if (ta_need(";") == 0) return 0;
        } else if (ta_tok_type == 1) {
            if (ta_assignment() == 0) return 0;
        } else { ta_error = 22; return 0; }
        if (is_single) {
            if (ta_add(1,0,0,0,ta_single_if) == 0) return 0;
            ta_single_if = 0;
        }
    }
    if (ta_depth != 0 | ta_single_if != 0 | ta_tok_type != 0) {
        ta_error = 23; return 0;
    }
    /* A scaled address expression must have exactly one array owner. */
    label = 0;
    while (label < tb_count) {
        if (tb_op[label] == 14 & tb_a[label] == 0) { ta_error = 24; return 0; }
        label = label + 1;
    }
    return tb_compile();
}
