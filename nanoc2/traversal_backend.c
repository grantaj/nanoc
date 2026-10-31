/*
 * Small semantic-tape 6502 emitter, first replacement-codegen experiment.
 *
 * The existing Nano C parser will supply typed operations; this file never
 * parses source text and does not recognize function names or loop shapes.
 * Its one planning decision is the physical meaning of X and Y in a region:
 * an index in indirect reads wants Y, otherwise a direct-array index wants X.
 *
 * This is Phase-1-shaped C: fixed arrays, no structures, recursion or malloc.
 * The host test supplies tb_char() and tb_name(); the native compiler can use
 * its existing text output and symbol-name functions in their place.
 */

/* Event codes: 1 label, 2 byte constant, 3 increment, 4 load array,
 * 5 compare array, 6 load indirect, 7 compare indirect, 8 compare immediate,
 * 9 compare a variable, 10 conditional branch, 11 jump, 12 return variable,
 * 13 return constant, 14 prepare scaled pointer, 15 load variable,
 * 16 set variable to A, 17 compare A with immediate,
 * 18 compare A with byte variable.
 * Locations 1..31 are byte variables; arrays use ids 1..31;
 * pointer slot 0/1 is a shared zero-page address.
 * Branch tests: 1 EQ, 2 NE, 3 CC, 4 CS. 0 is unconditional.
 */
char tb_op[192];
char tb_dst[192];
char tb_a[192];
char tb_b[192];
unsigned tb_num[192];
unsigned tb_count;
char tb_x;
char tb_y;
char tb_error;
unsigned tb_next_label;
char tb_digits[17] = "0123456789ABCDEF";

/* Provided by an integration adapter, deliberately not a second parser. */
char tb_char(char c);
char *tb_name(char category, char number);

char tb_text(char *s)
{
    unsigned i;
    i = 0;
    while (s[i] != 0) {
        if (tb_char(s[i]) == 0) return 0;
        i = i + 1;
    }
    return 1;
}

char tb_hex4(unsigned value)
{
    if (tb_char(tb_digits[(value >> 12) & 15]) == 0) return 0;
    if (tb_char(tb_digits[(value >> 8) & 15]) == 0) return 0;
    if (tb_char(tb_digits[(value >> 4) & 15]) == 0) return 0;
    return tb_char(tb_digits[value & 15]);
}

char tb_hex2(unsigned value)
{
    if (value > 255) { tb_error = 7; return 0; }
    if (tb_char(tb_digits[(value >> 4) & 15]) == 0) return 0;
    return tb_char(tb_digits[value & 15]);
}

char tb_simple(char *mnemonic)
{
    if (tb_text("\t") == 0) return 0;
    if (tb_text(mnemonic) == 0) return 0;
    return tb_char('\n');
}

char tb_operand(char *mnemonic, char *operand)
{
    if (tb_text("\t") == 0) return 0;
    if (tb_text(mnemonic) == 0) return 0;
    if (tb_char(' ') == 0) return 0;
    if (tb_text(operand) == 0) return 0;
    return tb_char('\n');
}

char tb_immediate(char *op, unsigned value)
{
    if (tb_text("\t") == 0) return 0;
    if (tb_text(op) == 0) return 0;
    if (tb_text(" #$") == 0) return 0;
    if (tb_hex2(value) == 0) return 0;
    return tb_char('\n');
}

char tb_location(char *op, char category, char symbol, char *suffix)
{
    if (tb_text("\t") == 0) return 0;
    if (tb_text(op) == 0) return 0;
    if (tb_char(' ') == 0) return 0;
    if (tb_text(tb_name(category,symbol)) == 0) return 0;
    if (tb_text(suffix) == 0) return 0;
    return tb_char('\n');
}

char tb_label(unsigned id)
{
    if (tb_text(".L") == 0) return 0;
    if (tb_hex4(id) == 0) return 0;
    return tb_text(":\n");
}

char tb_jump(char *op, unsigned id)
{
    if (tb_text("\t") == 0) return 0;
    if (tb_text(op) == 0) return 0;
    if (tb_text(" .L") == 0) return 0;
    if (tb_hex4(id) == 0) return 0;
    return tb_char('\n');
}

char tb_add(char op, char dest, char a, char b, unsigned number)
{
    if (tb_count >= 192) { tb_error = 1; return 0; }
    tb_op[tb_count] = op;
    tb_dst[tb_count] = dest;
    tb_a[tb_count] = a;
    tb_b[tb_count] = b;
    tb_num[tb_count] = number;
    tb_count = tb_count + 1;
    return 1;
}

char tb_reset()
{
    tb_count = 0;
    tb_error = 0;
    tb_x = 0;
    tb_y = 0;
    tb_next_label = 300;
    return 1;
}

/* Choose index register homes for *this function* before emitting anything.
 * The choice is independent of source symbol names and control shape.
 * We never keep a register home for an index simultaneously used in two
 * incompatible roles. A real integration will use the general spill path
 * for these conflicts; this first slice rejects them instead.
 */
char tb_plan()
{
    unsigned i;
    char indirect;
    char direct;
    char a;
    indirect = 0;
    direct = 0;
    i = 0;
    while (i < tb_count) {
        a = tb_b[i];
        if (tb_op[i] == 6 | tb_op[i] == 7) {
            if (indirect != 0 & indirect != a) {
                tb_error = 2;
                return 0;
            }
            indirect = a;
        }
        if (tb_op[i] == 4 | tb_op[i] == 5) {
            if (direct == 0) direct = a;
        }
        i = i + 1;
    }
    tb_y = indirect;
    if (direct != 0 & direct != indirect) tb_x = direct;
    if (tb_y == 0 & direct != 0) tb_x = direct;
    return 1;
}

char tb_load_index(char index, char *op, char array, char indirect)
{
    if (indirect != 0) {
        if (index != tb_y) {
            tb_error = 3;
            return 0;
        }
        if (tb_text("\t") == 0) return 0;
        if (tb_text(op) == 0) return 0;
        if (tb_text(" (__tptr") == 0) return 0;
        if (tb_hex2(array) == 0) return 0;
        return tb_text("),y\n");
    }
    if (index == tb_x) return tb_location(op, 2, array, ",x");
    if (index == tb_y) return tb_location(op, 2, array, ",y");
    /* A different source index must not overwrite a live Y loop index. */
    if (tb_y != 0) { tb_error = 8; return 0; }
    if (tb_location("ldy", 1, index, "") == 0) return 0;
    return tb_location(op, 2, array, ",y");
}

char tb_load_var(char v)
{
    if (v == tb_x) return tb_simple("txa");
    if (v == tb_y) return tb_simple("tya");
    return tb_location("lda",1,v,"");
}

char tb_store_var(char v)
{
    if (v == tb_x) return tb_simple("tax");
    if (v == tb_y) return tb_simple("tay");
    return tb_location("sta",1,v,"");
}

/* The scaled-address operation is algebraic, not a record-shaped template.
 * Currently it supports a power-of-two stride (1..128): shift a 16-bit
 * byte index until it becomes a byte offset, then add the array base.
 */
char tb_scaled_pointer(char ptr, char array, char index, unsigned stride)
{
    unsigned shift;
    unsigned remaining;
    if (stride == 0 | stride > 128) { tb_error = 4; return 0; }
    remaining = stride;
    shift = 0;
    while (remaining > 1) {
        if (remaining & 1) { tb_error = 4; return 0; }
        remaining = remaining >> 1;
        shift = shift + 1;
    }
    if (tb_load_var(index) == 0) return 0;
    if (tb_operand("sta","__twlo") == 0) return 0;
    if (tb_immediate("lda",0) == 0) return 0;
    if (tb_operand("sta","__twhi") == 0) return 0;
    while (shift != 0) {
        if (tb_operand("asl","__twlo") == 0) return 0;
        if (tb_operand("rol","__twhi") == 0) return 0;
        shift = shift - 1;
    }
    if (tb_simple("clc") == 0) return 0;
    if (tb_text("\tlda #<") == 0) return 0;
    if (tb_text(tb_name(2,array)) == 0) return 0;
    if (tb_char('\n') == 0) return 0;
    if (tb_operand("adc","__twlo") == 0) return 0;
    if (tb_text("\tsta __tptr") == 0) return 0;
    if (tb_hex2(ptr) == 0) return 0;
    if (tb_char('\n') == 0) return 0;
    if (tb_text("\tlda #>") == 0) return 0;
    if (tb_text(tb_name(2,array)) == 0) return 0;
    if (tb_char('\n') == 0) return 0;
    if (tb_operand("adc","__twhi") == 0) return 0;
    if (tb_text("\tsta __tptr") == 0) return 0;
    if (tb_hex2(ptr) == 0) return 0;
    return tb_text("+1\n");
}

char tb_compare(char variable, char other)
{
    if (variable == tb_x) {
        if (other == 0) return 0;
        return tb_location("cpx",1,other,"");
    }
    if (variable == tb_y) return tb_location("cpy",1,other,"");
    if (tb_load_var(variable) == 0) return 0;
    return tb_location("cmp",1,other,"");
}

char tb_compare_imm(char variable, unsigned value)
{
    if (variable == tb_x) return tb_immediate("cpx",value);
    if (variable == tb_y) return tb_immediate("cpy",value);
    if (tb_load_var(variable) == 0) return 0;
    return tb_immediate("cmp",value);
}

char tb_branch(char condition, unsigned dest)
{
    unsigned skip;
    char *inverse;
    if (condition == 0) return tb_jump("jmp",dest);
    /* Always-safe long conditional branch; relax only after correctness. */
    if (condition == 1) inverse = "bne";
    else if (condition == 2) inverse = "beq";
    else if (condition == 3) inverse = "bcs";
    else if (condition == 4) inverse = "bcc";
    else { tb_error = 5; return 0; }
    skip = tb_next_label;
    tb_next_label = tb_next_label + 1;
    if (tb_jump(inverse,skip) == 0) return 0;
    if (tb_jump("jmp",dest) == 0) return 0;
    return tb_label(skip);
}

char tb_compile()
{
    unsigned i;
    char op;
    char d;
    char a;
    char b;
    unsigned k;
    if (tb_error != 0) return 0;
    if (tb_plan() == 0) return 0;
    i = 0;
    while (i < tb_count) {
        op = tb_op[i]; d = tb_dst[i]; a = tb_a[i]; b = tb_b[i];
        k = tb_num[i];
        if (op == 1) {
            if (tb_label(k) == 0) return 0;
        } else if (op == 2) {
            if (d == tb_x) {
                if (tb_immediate("ldx",k) == 0) return 0;
            } else if (d == tb_y) {
                if (tb_immediate("ldy",k) == 0) return 0;
            } else {
                if (tb_immediate("lda",k) == 0) return 0;
                if (tb_store_var(d) == 0) return 0;
            }
        } else if (op == 3) {
            if (d == tb_x) {
                if (tb_simple("inx") == 0) return 0;
            } else if (d == tb_y) {
                if (tb_simple("iny") == 0) return 0;
            } else {
                if (tb_location("inc",1,d,"") == 0) return 0;
            }
        } else if (op == 4 | op == 5 | op == 6 | op == 7) {
            if (op == 4 | op == 6) {
                if (tb_load_index(b, "lda", a, op >= 6) == 0) return 0;
            } else {
                if (tb_load_index(b, "cmp", a, op >= 6) == 0) return 0;
            }
        } else if (op == 8) {
            if (tb_compare_imm(d,k) == 0) return 0;
        } else if (op == 9) {
            if (tb_compare(d,a) == 0) return 0;
        } else if (op == 10) {
            if (tb_branch(a,k) == 0) return 0;
        } else if (op == 11) {
            if (tb_branch(0,k) == 0) return 0;
        } else if (op == 12) {
            if (tb_load_var(d) == 0) return 0;
            if (tb_simple("rts") == 0) return 0;
        } else if (op == 13) {
            if (tb_immediate("lda",k) == 0) return 0;
            if (tb_simple("rts") == 0) return 0;
        } else if (op == 14) {
            if (tb_scaled_pointer(d,a,b,k) == 0) return 0;
        } else if (op == 15) {
            if (tb_load_var(a) == 0) return 0;
        } else if (op == 16) {
            if (tb_store_var(d) == 0) return 0;
        } else if (op == 17) {
            if (tb_immediate("cmp",k) == 0) return 0;
        } else if (op == 18) {
            if (tb_location("cmp",1,a,"") == 0) return 0;
        } else {
            tb_error = 6;
            return 0;
        }
        i = i + 1;
    }
    return 1;
}
