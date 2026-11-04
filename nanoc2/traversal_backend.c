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
 * 18 compare A with byte variable, 19 store fixed array indexed,
 * 20 store through zero-page pointer indexed, 21 load immediate byte,
 * 22 stage byte argument, 23 call char function, 25 load call result,
 * 26 return A, 27 store word literal, 28 copy word scalar,
 * 29 return word literal, 30 return word scalar,
 * 31/32 word +/- literal store, 33/34 word +/- literal return,
 * 35/36 word +/- word store, 37/38 word +/- word return,
 * 39/40 signed or unsigned word compare (variable/literal),
 * 41 word truth test, 42/43 word-call result store/return,
 * 44/45 word literal/variable argument, 46 byte-to-word argument,
 * 47 word-to-byte argument, 48/49 byte-call result promoted to word,
 * 50 init scratch word, 51 apply +/- leaf, 52 store chain,
 * 53 return chain, 54 zero-extend byte scalar to word home,
 * 58-61 word +/- byte scalar direct store/return,
 * 62/63 byte - word return/store, 64/65 byte+byte as word,
 * 66/67 byte+byte as byte store/return,
 * 68 compare mixed-width scalar/literal numeric operands,
 * 69 zero/nonzero test of the composed-arithmetic accumulator.
 * Calls synchronize X/Y into their real scalar homes, then reload those
 * homes after JSR. The callee is free to clobber the physical registers.
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
        if (tb_op[i] == 6 | tb_op[i] == 7 | tb_op[i] == 20) {
            if (indirect != 0 & indirect != a) {
                tb_error = 2;
                return 0;
            }
            indirect = a;
        }
        if (tb_op[i] == 4 | tb_op[i] == 5 | tb_op[i] == 19) {
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

/* Arguments use the original Nano C static parameter ABI. A callee's
 * argument slot is not an allocator temporary; it has a stable __vFF_00
 * home determined by the original Phase-1 symbol table.
 */
char tb_param(char *mnemonic, char callee, char argument, char *suffix)
{
    if(tb_char('\t')==0) return 0;
    if(tb_text(mnemonic)==0) return 0;
    if(tb_text(" __v")==0) return 0;
    if(tb_hex2(callee)==0) return 0;
    if(tb_char('_')==0) return 0;
    if(tb_hex2(argument)==0) return 0;
    if(tb_text(suffix)==0) return 0;
    return tb_char('\n');
}

char tb_stage_byte(char callee,char argument)
{
    return tb_param("sta",callee,argument,"");
}

/* A call ends a traversal register lifetime. Sync induction registers to
 * their actual scalar homes before JSR, then reload afterwards. This also
 * respects a callee's legitimate modification of global byte scalars.
 * Indirect pointer cursors are forbidden at the lowering boundary until
 * their full call-clobber contract is implemented.
 */
char tb_call_byte(char callee, char return_type)
{
    if(tb_x!=0) {
        if(tb_location("stx",1,tb_x,"")==0) return 0;
    }
    if(tb_y!=0) {
        if(tb_location("sty",1,tb_y,"")==0) return 0;
    }
    if(tb_text("\tjsr __c")==0) return 0;
    if(tb_hex2(callee)==0) return 0;
    if(tb_char('\n')==0) return 0;
    /* The callee returns a word in A/X, but X may also hold the
     * caller's induction variable. Save X before restoring that home.
     * Do not pay an extra STX for ordinary byte calls. */
    if(tb_operand("sta","__tret")==0) return 0;
    if(return_type==2) {
        if(tb_operand("stx","__trethi")==0) return 0;
    }
    if(tb_x!=0) {
        if(tb_location("ldx",1,tb_x,"")==0) return 0;
    }
    if(tb_y!=0) {
        if(tb_location("ldy",1,tb_y,"")==0) return 0;
    }
    return 1;
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

/* Small non-recursive primitive for a single processor-flag predicate. */
char tb_branch_single(char condition, unsigned dest)
{
    unsigned skip;
    char *inverse;
    if (condition==1) inverse="bne";
    else if (condition==2) inverse="beq";
    else if (condition==3) inverse="bcs";
    else if (condition==4) inverse="bcc";
    else { tb_error=5;return 0; }
    skip=tb_next_label;
    tb_next_label=tb_next_label+1;
    if(tb_jump(inverse,skip)==0) return 0;
    if(tb_jump("jmp",dest)==0) return 0;
    return tb_label(skip);
}

char tb_branch(char condition, unsigned dest)
{
    unsigned skip;
    if(condition==0) return tb_jump("jmp",dest);
    /* > is false when C=0 or Z=1; <= when C=1 and Z=0. */
    if(condition==5) {
        if(tb_branch_single(3,dest)==0) return 0;
        return tb_branch_single(1,dest);
    }
    if(condition==6) {
        skip=tb_next_label;
        tb_next_label=tb_next_label+1;
        if(tb_jump("bcc",skip)==0) return 0;
        if(tb_branch_single(2,dest)==0) return 0;
        return tb_label(skip);
    }
    return tb_branch_single(condition,dest);
}

/* Leave carry and zero set by a lexicographic 16-bit CMP: compare high
 * first, and compare low only when the high bytes are equal. If signed,
 * XOR $80 on high bytes to order signed words using the 6502 carry flag.
 * No flags-changing instruction may intervene before the branch. */
char tb_compare_word(char left, char right, char is_unsigned,
                     char literal, unsigned number)
{
    unsigned done;
    done=tb_next_label;
    tb_next_label=tb_next_label+1;
    if(is_unsigned==0) {
        if(literal==0) {
            if(tb_location("lda",1,right,"+1")==0) return 0;
            if(tb_immediate("eor",128)==0) return 0;
            if(tb_operand("sta","__twlo")==0) return 0;
        }
        if(tb_location("lda",1,left,"+1")==0) return 0;
        if(tb_immediate("eor",128)==0) return 0;
        if(literal!=0) {
            if(tb_immediate("cmp",(number >> 8)^128)==0) return 0;
        } else {
            if(tb_operand("cmp","__twlo")==0) return 0;
        }
    } else {
        if(tb_location("lda",1,left,"+1")==0) return 0;
        if(literal!=0) {
            if(tb_immediate("cmp",number >> 8)==0) return 0;
        } else {
            if(tb_location("cmp",1,right,"+1")==0) return 0;
        }
    }
    if(tb_jump("bne",done)==0) return 0;
    if(tb_location("lda",1,left,"")==0) return 0;
    if(literal!=0) {
        if(tb_immediate("cmp",number & 255)==0) return 0;
    } else {
        if(tb_location("cmp",1,right,"")==0) return 0;
    }
    return tb_label(done);
}

/* A byte operand can be held in X/Y as a live loop induction variable;
 * its static home is not necessarily current. Load directly from X/Y
 * when appropriate and compare/add via a single temporary otherwise. */
char tb_add_bytes(char left, char right)
{
    if(right==tb_x) {
        if(tb_operand("stx","__twlo")==0) return 0;
    }
    if(right==tb_y) {
        if(tb_operand("sty","__twlo")==0) return 0;
    }
    if(tb_load_var(left)==0) return 0;
    if(tb_simple("clc")==0) return 0;
    if(right==tb_x | right==tb_y)
        return tb_operand("adc","__twlo");
    return tb_location("adc",1,right,"");
}

/* Full-width comparison with at most one literal.
 * Rather than materialising either promoted char as a 16-bit temporary,
 * its upper byte is the immediate zero. Signed ordering biases each
 * high byte by $80; unsigned ordering compares the original high byte.
 * The original typed parser decides which comparison mode applies.
 *
 * An X/Y-carried byte is read from its register, never its stale home.
 * The final high/low CMP leaves both C and Z ready for tb_branch(). */
char tb_numeric_high(char kind, char home, unsigned literal, char bias)
{
    if(kind==1) return tb_immediate("lda",(literal >> 8)^bias);
    if(kind==2) return tb_immediate("lda",bias);
    if(kind==3) {
        if(home==0) {
            if(tb_operand("lda","__tacc+1")==0) return 0;
        } else {
            if(tb_location("lda",1,home,"+1")==0) return 0;
        }
        if(bias!=0) return tb_immediate("eor",bias);
        return 1;
    }
    tb_error=68;
    return 0;
}

char tb_numeric_compare(char left, char right, char descriptor,
                        unsigned literal)
{
    unsigned done;
    char lk;
    char rk;
    char bias;
    lk=(descriptor >> 3)&7;
    rk=descriptor&7;
    bias=0;
    if((descriptor & 64)==0) bias=128;
    if(lk<1 | lk>3 | rk<1 | rk>3 | (lk==1 & rk==1)) {
        tb_error=70+lk*8+rk; return 0;
    }
    /* A signed word RHS needs a high-byte bias. Compute it first,
     * leaving A free to load the LHS, then compare against scratch. */
    if(bias!=0 & rk==3) {
        if(tb_location("lda",1,right,"+1")==0) return 0;
        if(tb_immediate("eor",bias)==0) return 0;
        if(tb_operand("sta","__twlo")==0) return 0;
    }
    if(tb_numeric_high(lk,left,literal,bias)==0) return 0;
    if(rk==1) {
        if(tb_immediate("cmp",(literal >> 8)^bias)==0) return 0;
    } else if(rk==2) {
        if(tb_immediate("cmp",bias)==0) return 0;
    } else if(bias!=0) {
        if(tb_operand("cmp","__twlo")==0) return 0;
    } else {
        if(tb_location("cmp",1,right,"+1")==0) return 0;
    }
    done=tb_next_label;
    tb_next_label=tb_next_label+1;
    if(tb_jump("bne",done)==0) return 0;
    if(lk==1) {
        if(tb_immediate("lda",literal&255)==0) return 0;
    } else if(lk==2) {
        if(tb_load_var(left)==0) return 0;
    } else {
        if(left==0) {
            if(tb_operand("lda","__tacc")==0) return 0;
        } else {
            if(tb_location("lda",1,left,"")==0) return 0;
        }
    }
    if(rk==1) {
        if(tb_immediate("cmp",literal&255)==0) return 0;
    } else if(rk==2) {
        /* A register-held index may not have been spilled to its
         * static home. STX/STY preserve A and the compare flags. */
        if(right==tb_x) {
            if(tb_operand("stx","__twlo")==0) return 0;
            if(tb_operand("cmp","__twlo")==0) return 0;
        } else if(right==tb_y) {
            if(tb_operand("sty","__twlo")==0) return 0;
            if(tb_operand("cmp","__twlo")==0) return 0;
        } else {
            if(tb_location("cmp",1,right,"")==0) return 0;
        }
    } else {
        if(tb_location("cmp",1,right,"")==0) return 0;
    }
    return tb_label(done);
}

char tb_compile()
{
    unsigned i;
    char op;
    char d;
    char a;
    char b;
    unsigned k;
    char *word_op;
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
        } else if (op == 19 | op == 20) {
            /* The RHS is already in A. Indexed addressing does not
             * clobber it; X/Y were planned before this loop began. */
            if (tb_load_index(b, "sta", a, op == 20) == 0) return 0;
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
            /* Nano C char result: A contains the byte, X is zero. */
            if (tb_immediate("ldx",0) == 0) return 0;
            if (tb_simple("rts") == 0) return 0;
        } else if (op == 13) {
            if (tb_immediate("lda",k) == 0) return 0;
            if (tb_immediate("ldx",0) == 0) return 0;
            if (tb_simple("rts") == 0) return 0;
        } else if (op == 14) {
            if (tb_scaled_pointer(d,a,b,k) == 0) return 0;
        } else if (op == 15) {
            if (tb_load_var(a) == 0) return 0;
        } else if (op == 16) {
            if (tb_store_var(d) == 0) return 0;
        } else if (op == 21) {
            if (tb_immediate("lda",k) == 0) return 0;
        } else if (op == 22) {
            if (tb_stage_byte(d,a)==0) return 0;
        } else if (op == 23) {
            if (tb_call_byte(d,a)==0) return 0;
        } else if (op == 27) {
            /* Two-byte Nano C int/unsigned static home. */
            if (tb_immediate("lda",k & 255)==0) return 0;
            if (tb_location("sta",1,d,"")==0) return 0;
            if (tb_immediate("lda",k >> 8)==0) return 0;
            if (tb_location("sta",1,d,"+1")==0) return 0;
        } else if (op == 28) {
            if (tb_location("lda",1,a,"")==0) return 0;
            if (tb_location("sta",1,d,"")==0) return 0;
            if (tb_location("lda",1,a,"+1")==0) return 0;
            if (tb_location("sta",1,d,"+1")==0) return 0;
        } else if (op == 29) {
            if (tb_immediate("lda",k & 255)==0) return 0;
            if (tb_immediate("ldx",k >> 8)==0) return 0;
            if (tb_simple("rts")==0) return 0;
        } else if (op == 30) {
            if (tb_location("lda",1,d,"")==0) return 0;
            if (tb_location("ldx",1,d,"+1")==0) return 0;
            if (tb_simple("rts")==0) return 0;
        } else if (op == 31 | op == 32) {
            /* Ordinary 6502 16-bit add/sub with carry or borrow.
             * Keep the high source byte untouched until it is read so
             * in-place updates are safe, even across a page boundary. */
            if (op==31) {
                if (tb_simple("clc")==0) return 0;
                word_op="adc";
            } else {
                if (tb_simple("sec")==0) return 0;
                word_op="sbc";
            }
            if (tb_location("lda",1,a,"")==0) return 0;
            if (tb_immediate(word_op,k & 255)==0) return 0;
            if (tb_location("sta",1,d,"")==0) return 0;
            if (tb_location("lda",1,a,"+1")==0) return 0;
            if (tb_immediate(word_op,k >> 8)==0) return 0;
            if (tb_location("sta",1,d,"+1")==0) return 0;
        } else if (op == 33 | op == 34) {
            /* Word ABI: A=low, X=high. Save the low result in private
             * scratch while the second byte consumes the same carry. */
            if (op==33) {
                if (tb_simple("clc")==0) return 0;
                word_op="adc";
            } else {
                if (tb_simple("sec")==0) return 0;
                word_op="sbc";
            }
            if (tb_location("lda",1,d,"")==0) return 0;
            if (tb_immediate(word_op,k & 255)==0) return 0;
            if (tb_operand("sta","__twlo")==0) return 0;
            if (tb_location("lda",1,d,"+1")==0) return 0;
            if (tb_immediate(word_op,k >> 8)==0) return 0;
            if (tb_simple("tax")==0) return 0;
            if (tb_operand("lda","__twlo")==0) return 0;
            if (tb_simple("rts")==0) return 0;
        } else if (op == 35 | op == 36 | op == 37 | op == 38) {
            if (op==35 | op==37) {
                if(tb_simple("clc")==0) return 0;
                word_op="adc";
            } else {
                if(tb_simple("sec")==0) return 0;
                word_op="sbc";
            }
            if(tb_location("lda",1,a,"")==0) return 0;
            if(tb_location(word_op,1,b,"")==0) return 0;
            if(op==35 | op==36) {
                if(tb_location("sta",1,d,"")==0) return 0;
            } else {
                if(tb_operand("sta","__twlo")==0) return 0;
            }
            if(tb_location("lda",1,a,"+1")==0) return 0;
            if(tb_location(word_op,1,b,"+1")==0) return 0;
            if(op==35 | op==36) {
                if(tb_location("sta",1,d,"+1")==0) return 0;
            } else {
                if(tb_simple("tax")==0) return 0;
                if(tb_operand("lda","__twlo")==0) return 0;
                if(tb_simple("rts")==0) return 0;
            }
        } else if (op == 39) {
            if(tb_compare_word(d,a,b,0,0)==0) return 0;
        } else if (op == 40) {
            if(tb_compare_word(d,0,a,1,k)==0) return 0;
        } else if (op == 41) {
            if(tb_location("lda",1,d,"")==0) return 0;
            if(tb_location("ora",1,d,"+1")==0) return 0;
        } else if (op == 42 | op == 48) {
            if(tb_operand("lda","__tret")==0) return 0;
            if(tb_location("sta",1,d,"")==0) return 0;
            if(op==42) {
                if(tb_operand("lda","__trethi")==0) return 0;
            } else {
                if(tb_immediate("lda",0)==0) return 0;
            }
            if(tb_location("sta",1,d,"+1")==0) return 0;
        } else if (op == 43 | op == 49) {
            if(op==43) {
                if(tb_operand("ldx","__trethi")==0) return 0;
            } else {
                if(tb_immediate("ldx",0)==0) return 0;
            }
            if(tb_operand("lda","__tret")==0) return 0;
            if(tb_simple("rts")==0) return 0;
        } else if (op == 44) {
            if(tb_immediate("lda",k&255)==0) return 0;
            if(tb_param("sta",d,a,"")==0) return 0;
            if(tb_immediate("lda",k>>8)==0) return 0;
            if(tb_param("sta",d,a,"+1")==0) return 0;
        } else if (op == 45) {
            if(tb_location("lda",1,b,"")==0) return 0;
            if(tb_param("sta",d,a,"")==0) return 0;
            if(tb_location("lda",1,b,"+1")==0) return 0;
            if(tb_param("sta",d,a,"+1")==0) return 0;
        } else if (op == 46) {
            if(tb_load_var(b)==0) return 0;
            if(tb_param("sta",d,a,"")==0) return 0;
            if(tb_immediate("lda",0)==0) return 0;
            if(tb_param("sta",d,a,"+1")==0) return 0;
        } else if (op == 47) {
            if(tb_location("lda",1,b,"")==0) return 0;
            if(tb_param("sta",d,a,"")==0) return 0;
        } else if (op == 50) {
            /* Materialise the leftmost scalar or literal into a private
             * two-byte accumulator. No source home is changed yet. */
            if(d==1) {
                if(tb_immediate("lda",k&255)==0) return 0;
            } else if(d==2) {
                if(tb_load_var(a)==0) return 0;
            } else if(d==3) {
                if(tb_location("lda",1,a,"")==0) return 0;
            } else {tb_error=50;return 0;}
            if(tb_operand("sta","__tacc")==0) return 0;
            if(d==1) {
                if(tb_immediate("lda",k>>8)==0) return 0;
            } else if(d==2) {
                if(tb_immediate("lda",0)==0) return 0;
            } else {
                if(tb_location("lda",1,a,"+1")==0) return 0;
            }
            if(tb_operand("sta","__tacc+1")==0) return 0;
        } else if (op == 51) {
            /* Operands in X/Y may have stale static homes while the loop
             * register is live. Snapshot the byte before changing A. */
            if(a==2 & b==tb_x) {
                if(tb_operand("stx","__twlo")==0) return 0;
            }
            if(a==2 & b==tb_y) {
                if(tb_operand("sty","__twlo")==0) return 0;
            }
            if(d=='+') {
                if(tb_simple("clc")==0) return 0;
                word_op="adc";
            } else if(d=='-') {
                if(tb_simple("sec")==0) return 0;
                word_op="sbc";
            } else {tb_error=51;return 0;}
            if(tb_operand("lda","__tacc")==0) return 0;
            if(a==1) {
                if(tb_immediate(word_op,k&255)==0) return 0;
            } else if(a==2 & (b==tb_x | b==tb_y)) {
                if(tb_operand(word_op,"__twlo")==0) return 0;
            } else if(a==2 | a==3) {
                if(tb_location(word_op,1,b,"")==0) return 0;
            } else {tb_error=51;return 0;}
            if(tb_operand("sta","__tacc")==0) return 0;
            if(tb_operand("lda","__tacc+1")==0) return 0;
            if(a==1) {
                if(tb_immediate(word_op,k>>8)==0) return 0;
            } else if(a==2) {
                if(tb_immediate(word_op,0)==0) return 0;
            } else {
                if(tb_location(word_op,1,b,"+1")==0) return 0;
            }
            if(tb_operand("sta","__tacc+1")==0) return 0;
        } else if (op == 52) {
            if(tb_operand("lda","__tacc")==0) return 0;
            if(a==1) {
                if(tb_store_var(d)==0) return 0;
            } else if(a==2 | a==3) {
                if(tb_location("sta",1,d,"")==0) return 0;
                if(tb_operand("lda","__tacc+1")==0) return 0;
                if(tb_location("sta",1,d,"+1")==0) return 0;
            } else {tb_error=52;return 0;}
        } else if (op == 53) {
            if(d==1) {
                if(tb_operand("lda","__tacc")==0) return 0;
                if(tb_immediate("ldx",0)==0) return 0;
            } else if(d==2 | d==3) {
                if(tb_operand("ldx","__tacc+1")==0) return 0;
                if(tb_operand("lda","__tacc")==0) return 0;
            } else {tb_error=53;return 0;}
            if(tb_simple("rts")==0) return 0;
        } else if (op == 54) {
            if(tb_load_var(a)==0) return 0;
            if(tb_location("sta",1,d,"")==0) return 0;
            if(tb_immediate("lda",0)==0) return 0;
            if(tb_location("sta",1,d,"+1")==0) return 0;
        } else if (op == 58 | op == 59 | op == 60 | op == 61) {
            /* Single word +/- byte: the 6502 carry chain naturally
             * handles the implicit zero high byte without a scratch
             * accumulator. Preserve the loop index in X/Y. */
            if(b==tb_x) {
                if(tb_operand("stx","__twlo")==0) return 0;
            }
            if(b==tb_y) {
                if(tb_operand("sty","__twlo")==0) return 0;
            }
            if(op==58 | op==60) {
                if(tb_simple("clc")==0) return 0;
                word_op="adc";
            } else {
                if(tb_simple("sec")==0) return 0;
                word_op="sbc";
            }
            if(tb_location("lda",1,a,"")==0) return 0;
            if(b==tb_x | b==tb_y) {
                if(tb_operand(word_op,"__twlo")==0) return 0;
            } else {
                if(tb_location(word_op,1,b,"")==0) return 0;
            }
            if(op==58 | op==59) {
                if(tb_location("sta",1,d,"")==0) return 0;
            } else {
                if(tb_operand("sta","__twlo")==0) return 0;
            }
            if(tb_location("lda",1,a,"+1")==0) return 0;
            if(tb_immediate(word_op,0)==0) return 0;
            if(op==58 | op==59) {
                if(tb_location("sta",1,d,"+1")==0) return 0;
            } else {
                if(tb_simple("tax")==0) return 0;
                if(tb_operand("lda","__twlo")==0) return 0;
                if(tb_simple("rts")==0) return 0;
            }
        } else if (op == 62 | op == 63) {
            /* Zero-extended byte minus a full word, with borrow into
             * the high byte. Cannot reverse operands as with addition. */
            if(tb_load_var(a)==0) return 0;
            if(tb_simple("sec")==0) return 0;
            if(tb_location("sbc",1,b,"")==0) return 0;
            if(op==62) {
                if(tb_operand("sta","__twlo")==0) return 0;
            } else {
                if(tb_location("sta",1,d,"")==0) return 0;
            }
            if(tb_immediate("lda",0)==0) return 0;
            if(tb_location("sbc",1,b,"+1")==0) return 0;
            if(op==62) {
                if(tb_simple("tax")==0) return 0;
                if(tb_operand("lda","__twlo")==0) return 0;
                if(tb_simple("rts")==0) return 0;
            } else {
                if(tb_location("sta",1,d,"+1")==0) return 0;
            }
        } else if (op == 64 | op == 65 | op == 66 | op == 67) {
            if(tb_add_bytes(a,b)==0) return 0;
            if(op==64) {
                if(tb_operand("sta","__twlo")==0) return 0;
                if(tb_immediate("lda",0)==0) return 0;
                if(tb_immediate("adc",0)==0) return 0;
                if(tb_simple("tax")==0) return 0;
                if(tb_operand("lda","__twlo")==0) return 0;
                if(tb_simple("rts")==0) return 0;
            } else if(op==65) {
                if(tb_location("sta",1,d,"")==0) return 0;
                if(tb_immediate("lda",0)==0) return 0;
                if(tb_immediate("adc",0)==0) return 0;
                if(tb_location("sta",1,d,"+1")==0) return 0;
            } else if(op==66) {
                if(tb_store_var(d)==0) return 0;
            } else {
                if(tb_immediate("ldx",0)==0) return 0;
                if(tb_simple("rts")==0) return 0;
            }
        } else if (op == 68) {
            if(tb_numeric_compare(d,a,b,k)==0) return 0;
        } else if (op == 69) {
            if(tb_operand("lda","__tacc")==0) return 0;
            if(tb_operand("ora","__tacc+1")==0) return 0;
        } else if (op == 25) {
            if (tb_operand("lda","__tret")==0) return 0;
        } else if (op == 26) {
            if (tb_immediate("ldx",0)==0) return 0;
            if (tb_simple("rts")==0) return 0;
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
