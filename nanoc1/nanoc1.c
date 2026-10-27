/*
 * nanoc1.c -- first Nano C compiler written in Nano C Phase 1.
 *
 * This is deliberately the semantic baseline.  Values are materialised as
 * ordinary 16-bit A/X pairs and expressions use a bounded hardware-stack value
 * stack.  The later #102 machine pass is allowed to replace that lowering; this
 * source first makes the language implementation explicit and trustworthy.
 */

/* token kinds above the ASCII range */

/* source types */

/* persistent symbols */

/* expression operators/markers */

/* control frames */

/* compact diagnostics */

/*
 * fixed_text is a single indexed character pool, not a general string system.
 * Phase 1 has no named compile-time constants or string escape sequences, and
 * this arrangement preserves nanoc0's tight symbol/initialisation budgets.
 * Each byte string below is labelled with its starting offset. When editing
 * it, update the corresponding fixed_text + offset uses together.
 * The first 21 bytes hold the filename of the source-selection job file.
 * Its fixed-size slot keeps every other offset unchanged.
 */
/* compact templates appended at offsets: push_ax=694, pop_ax=710, binary_prelude=726, add16=778, sub16=830, and16=882, or16=929, neg16=976, keyword_table=1072, two_char_operator_table=1090 */
/* more compact templates: shift_prefix=1111, shift_left=1124, shift_right=1173, shift_dec=1222, index_load_char=1228, index_load_word=1280, index_store_char=1372, index_store_word=1483, scale_index=1629, array_add_lo=1674, array_mid=1687, array_end=1713, ptr_add_lo=1729, ptr_mid=1740, ptr_high_suffix=1764 */
char job_source[64];

char fixed_text[1952] = {
    /*   0: BUILD/N1JOB - input job filename (21-byte reserved slot) */
    'B','U','I','L','D','/','N','1','J','O','B',0,0,0,0,0,0,0,0,0,0,
    /*  21: N1OUT.ASM */
    'N','1','O','U','T','.','A','S','M',0,
    /*  31: char */
    'c','h','a','r',0,
    /*  36: int */
    'i','n','t',0,
    /*  40: unsigned */
    'u','n','s','i','g','n','e','d',0,
    /*  49: if */
    'i','f',0,
    /*  52: else */
    'e','l','s','e',0,
    /*  57: while */
    'w','h','i','l','e',0,
    /*  63: break */
    'b','r','e','a','k',0,
    /*  69: return */
    'r','e','t','u','r','n',0,
    /*  76: io_open */
    'i','o','_','o','p','e','n',0,
    /*  84: io_read */
    'i','o','_','r','e','a','d',0,
    /*  92: io_create */
    'i','o','_','c','r','e','a','t','e',0,
    /* 102: io_write */
    'i','o','_','w','r','i','t','e',0,
    /* 111: io_close */
    'i','o','_','c','l','o','s','e',0,
    /* 120: main */
    'm','a','i','n',0,
    /* 125: ../nanoc1/target/header.asm */
    '.','.','/','n','a','n','o','c','1','/','t','a','r','g','e','t','/','h','e','a','d','e','r','.','a','s','m',0,
    /* 153: ../nanoc1/target/runtime.asm */
    '.','.','/','n','a','n','o','c','1','/','t','a','r','g','e','t','/','r','u','n','t','i','m','e','.','a','s','m',0,
    /* 182: include  */
    'i','n','c','l','u','d','e',' ',0,
    /* 191: NC_BSS */
    'N','C','_','B','S','S',0,
    /* 198: NC_TMP */
    'N','C','_','T','M','P',0,
    /* 205: NC_PTR */
    'N','C','_','P','T','R',0,
    /* 212: __nc_bss_bytes */
    '_','_','n','c','_','b','s','s','_','b','y','t','e','s',0,
    /* 227: __nc_entry */
    '_','_','n','c','_','e','n','t','r','y',0,
    /* 238: __nc_init */
    '_','_','n','c','_','i','n','i','t',0,
    /* 248: __c_io_open */
    '_','_','c','_','i','o','_','o','p','e','n',0,
    /* 260: __c_io_read */
    '_','_','c','_','i','o','_','r','e','a','d',0,
    /* 272: __c_io_create */
    '_','_','c','_','i','o','_','c','r','e','a','t','e',0,
    /* 286: __c_io_write */
    '_','_','c','_','i','o','_','w','r','i','t','e',0,
    /* 299: __c_io_close */
    '_','_','c','_','i','o','_','c','l','o','s','e',0,
    /* 312: __nc_eq16 */
    '_','_','n','c','_','e','q','1','6',0,
    /* 322: __nc_ne16 */
    '_','_','n','c','_','n','e','1','6',0,
    /* 332: __nc_ult16 */
    '_','_','n','c','_','u','l','t','1','6',0,
    /* 343: __nc_ule16 */
    '_','_','n','c','_','u','l','e','1','6',0,
    /* 354: __nc_ugt16 */
    '_','_','n','c','_','u','g','t','1','6',0,
    /* 365: __nc_uge16 */
    '_','_','n','c','_','u','g','e','1','6',0,
    /* 376: __nc_slt16 */
    '_','_','n','c','_','s','l','t','1','6',0,
    /* 387: __nc_sle16 */
    '_','_','n','c','_','s','l','e','1','6',0,
    /* 398: __nc_sgt16 */
    '_','_','n','c','_','s','g','t','1','6',0,
    /* 409: __nc_sge16 */
    '_','_','n','c','_','s','g','e','1','6',0,
    /* 420: __nc_mul16 */
    '_','_','n','c','_','m','u','l','1','6',0,
    /* 431: lda */
    'l','d','a',0,
    /* 435: ldx */
    'l','d','x',0,
    /* 439: ldy */
    'l','d','y',0,
    /* 443: sta */
    's','t','a',0,
    /* 447: stx */
    's','t','x',0,
    /* 451: pha */
    'p','h','a',0,
    /* 455: pla */
    'p','l','a',0,
    /* 459: txa */
    't','x','a',0,
    /* 463: tax */
    't','a','x',0,
    /* 467: tay */
    't','a','y',0,
    /* 471: tya */
    't','y','a',0,
    /* 475: clc */
    'c','l','c',0,
    /* 479: sec */
    's','e','c',0,
    /* 483: adc */
    'a','d','c',0,
    /* 487: sbc */
    's','b','c',0,
    /* 491: and */
    'a','n','d',0,
    /* 495: ora */
    'o','r','a',0,
    /* 499: asl */
    'a','s','l',0,
    /* 503: rol */
    'r','o','l',0,
    /* 507: lsr */
    'l','s','r',0,
    /* 511: ror */
    'r','o','r',0,
    /* 515: iny */
    'i','n','y',0,
    /* 519: dey */
    'd','e','y',0,
    /* 523: beq */
    'b','e','q',0,
    /* 527: bne */
    'b','n','e',0,
    /* 531: jmp */
    'j','m','p',0,
    /* 535: jsr */
    'j','s','r',0,
    /* 539: rts */
    'r','t','s',0,
    /* 543: eor */
    'e','o','r',0,
    /* 547: #< */
    ' ','#','<',0,
    /* 551: #> */
    ' ','#','>',0,
    /* 555: (NC_PTR),y */
    ' ','(','N','C','_','P','T','R',')',',','y',0,
    /* 567: = $ */
    ' ','=',' ','$',0,
    /* 572: = NC_BSS+$ */
    ' ','=',' ','N','C','_','B','S','S','+','$',0,
    /* 584: +1 */
    '+','1',0,
    /* 587: __L */
    '_','_','L',0,
    /* 591: __c_io_close__v0 */
    '_','_','c','_','i','o','_','c','l','o','s','e','_','_','v','0',0,
    /* 608: __c_io_create__v0 */
    '_','_','c','_','i','o','_','c','r','e','a','t','e','_','_','v','0',0,
    /* 626: __c_io_open__v0 */
    '_','_','c','_','i','o','_','o','p','e','n','_','_','v','0',0,
    /* 642: __c_io_read__v0 */
    '_','_','c','_','i','o','_','r','e','a','d','_','_','v','0',0,
    /* 658: __c_io_write__v0 */
    '_','_','c','_','i','o','_','w','r','i','t','e','_','_','v','0',0,
    /* 675: __f */
    '_','_','f',0,
    /* 679: __g */
    '_','_','g',0,
    /* 683: __v */
    '_','_','v',0,
    /* 687: byte $ */
    'b','y','t','e',' ','$',0,
    /* 694 onwards: compact byte templates for the direct 6502 emitter. */
    9,112,104,97,10,9,116,120,97,10,9,112,104,97,10,0,
    9,112,108,97,10,9,116,97,120,10,9,112,108,97,10,0,
    9,112,108,97,10,9,115,116,97,32,78,67,95,84,77,80,
    43,49,10,9,112,108,97,10,9,115,116,97,32,78,67,95,
    84,77,80,10,9,112,108,97,10,9,116,97,120,10,9,112,
    108,97,10,0,9,99,108,99,10,9,97,100,99,32,78,67,
    95,84,77,80,10,9,116,97,121,10,9,116,120,97,10,9,
    97,100,99,32,78,67,95,84,77,80,43,49,10,9,116,97,
    120,10,9,116,121,97,10,0,9,115,101,99,10,9,115,98,
    99,32,78,67,95,84,77,80,10,9,116,97,121,10,9,116,
    120,97,10,9,115,98,99,32,78,67,95,84,77,80,43,49,
    10,9,116,97,120,10,9,116,121,97,10,0,9,97,110,100,
    32,78,67,95,84,77,80,10,9,116,97,121,10,9,116,120,
    97,10,9,97,110,100,32,78,67,95,84,77,80,43,49,10,
    9,116,97,120,10,9,116,121,97,10,0,9,111,114,97,32,
    78,67,95,84,77,80,10,9,116,97,121,10,9,116,120,97,
    10,9,111,114,97,32,78,67,95,84,77,80,43,49,10,9,
    116,97,120,10,9,116,121,97,10,0,9,112,108,97,10,9,
    116,97,120,10,9,112,108,97,10,9,101,111,114,32,35,36,
    102,102,10,9,99,108,99,10,9,97,100,99,32,35,36,48,
    49,10,9,116,97,121,10,9,116,120,97,10,9,101,111,114,
    32,35,36,102,102,10,9,97,100,99,32,35,36,48,48,10,
    9,116,97,120,10,9,116,121,97,10,9,112,104,97,10,9,
    116,120,97,10,9,112,104,97,10,0,31,4,36,3,40,8,
    49,2,52,4,57,5,63,5,69,6,0,0,61,61,142,33,
    61,143,60,61,144,62,61,145,60,60,146,62,62,147,0,0,
    0,9,108,100,121,32,78,67,95,84,77,80,10,0,9,97,
    115,108,10,9,115,116,97,32,78,67,95,84,77,80,43,49,
    10,9,116,120,97,10,9,114,111,108,10,9,116,97,120,10,
    9,108,100,97,32,78,67,95,84,77,80,43,49,10,0,9,
    115,116,97,32,78,67,95,84,77,80,43,49,10,9,116,120,
    97,10,9,108,115,114,10,9,116,97,120,10,9,108,100,97,
    32,78,67,95,84,77,80,43,49,10,9,114,111,114,10,0,
    9,100,101,121,10,0,9,108,100,121,32,35,36,48,48,10,
    9,108,100,97,32,40,78,67,95,80,84,82,41,44,121,10,
    9,108,100,120,32,35,36,48,48,10,9,112,104,97,10,9,
    116,120,97,10,9,112,104,97,10,0,9,108,100,121,32,35,
    36,48,48,10,9,108,100,97,32,40,78,67,95,80,84,82,
    41,44,121,10,9,115,116,97,32,78,67,95,84,77,80,10,
    9,105,110,121,10,9,108,100,97,32,40,78,67,95,80,84,
    82,41,44,121,10,9,116,97,120,10,9,108,100,97,32,78,
    67,95,84,77,80,10,9,112,104,97,10,9,116,120,97,10,
    9,112,104,97,10,0,9,112,108,97,10,9,115,116,97,32,
    78,67,95,84,77,80,43,49,10,9,112,108,97,10,9,115,
    116,97,32,78,67,95,84,77,80,10,9,112,108,97,10,9,
    115,116,97,32,78,67,95,80,84,82,43,49,10,9,112,108,
    97,10,9,115,116,97,32,78,67,95,80,84,82,10,9,108,
    100,121,32,35,36,48,48,10,9,108,100,97,32,78,67,95,
    84,77,80,10,9,115,116,97,32,40,78,67,95,80,84,82,
    41,44,121,10,0,9,112,108,97,10,9,115,116,97,32,78,
    67,95,84,77,80,43,49,10,9,112,108,97,10,9,115,116,
    97,32,78,67,95,84,77,80,10,9,112,108,97,10,9,115,
    116,97,32,78,67,95,80,84,82,43,49,10,9,112,108,97,
    10,9,115,116,97,32,78,67,95,80,84,82,10,9,108,100,
    121,32,35,36,48,48,10,9,108,100,97,32,78,67,95,84,
    77,80,10,9,115,116,97,32,40,78,67,95,80,84,82,41,
    44,121,10,9,105,110,121,10,9,108,100,97,32,78,67,95,
    84,77,80,43,49,10,9,115,116,97,32,40,78,67,95,80,
    84,82,41,44,121,10,0,9,97,115,108,10,9,115,116,97,
    32,78,67,95,84,77,80,10,9,116,120,97,10,9,114,111,
    108,10,9,116,97,120,10,9,108,100,97,32,78,67,95,84,
    77,80,10,0,9,99,108,99,10,9,97,100,99,32,35,60,
    0,10,9,115,116,97,32,78,67,95,80,84,82,10,9,116,
    120,97,10,9,97,100,99,32,35,62,0,10,9,115,116,97,
    32,78,67,95,80,84,82,43,49,10,0,9,99,108,99,10,
    9,97,100,99,32,0,10,9,115,116,97,32,78,67,95,80,
    84,82,10,9,116,120,97,10,9,97,100,99,32,0,43,49,
    10,9,115,116,97,32,78,67,95,80,84,82,43,49,10,0,
    /* 1782: generic pointer-value indexed byte load */
    9,112,108,97,10,9,116,97,120,10,9,112,108,97,10,9,115,116,97,32,78,67,95,84,77,80,10,9,115,116,120,32,78,67,95,84,77,80,43,49,10,9,112,108,97,10,9,116,97,120,10,9,112,108,97,10,9,99,108,99,10,9,97,100,99,32,78,67,95,84,77,80,10,9,115,116,97,32,78,67,95,80,84,82,10,9,116,120,97,10,9,97,100,99,32,78,67,95,84,77,80,43,49,10,9,115,116,97,32,78,67,95,80,84,82,43,49,10,9,108,100,121,32,35,36,48,48,10,9,108,100,97,32,40,78,67,95,80,84,82,41,44,121,10,9,108,100,120,32,35,36,48,48,10,9,112,104,97,10,9,116,120,97,10,9,112,104,97,10,0
};

/*
 * Compact codes used in the bounded tables:
 *   tokens: 128 EOF, 129 error, 130 identifier, 131 integer,
 *           132 character, 133 string, 134..141 keywords,
 *           142 ==, 143 !=, 144 <=, 145 >=, 146 <<, 147 >>
 *   types:  1 char, 2 int, 3 unsigned, 4 char *
 *   symbols: 1 scalar, 2 array, 3 C function, 4 runtime function
 *   areas:  1 persistent/global, 2 current function
 *   expression markers: 200 unary minus, 201 group, 202 call, 203 index
 *   control frames: 1 block, 2 if-true, 3 if-else, 4 while
 *
 * These would conventionally be enums or macros.  Phase 1 has neither; keeping
 * the mapping in one visible comment is clearer than spending scarce persistent
 * bootstrap symbols on dozens of one-byte pseudo-constants.
 */

/* scanner text and source state */
char token_text[192];
char token_kind;
char token_type;
char token_length;
unsigned token_value;
int source_handle;
int output_handle;
int source_char;
int source_hold;
char hold_valid;
unsigned source_line;
char compiler_error;

/* fixed symbol model: flat names keep Phase 1 data structures obvious */
char global_name[5632];
char global_name_len[176];
char global_kind[176];
char global_type[176];
unsigned global_array_len[176];
char global_param_start[176];
char global_param_count[176];
char global_count;

char local_name[1024];
char local_name_len[32];
char local_type[32];
char local_count;
char current_func;

char param_type[128];
char param_count;

char pending_name[32];
char pending_length;

/* bounded expression parser state */
char op_code[32];
char op_aux[32];
char op_area[32];
char op_argc[32];
char op_base[32];
char op_top;
char value_type[32];
char value_top;
char expr_type;
char expr_expect;
char expr_done;
/* One finished expression value may remain in A/X until its consumer is known. */
char ax_pending;

/* bounded structured-control state */
char ctrl_kind[16];
unsigned ctrl_label0[16];
unsigned ctrl_label1[16];
char ctrl_top;

/* target layout and generated labels */
unsigned bss_offset;
unsigned label_counter;
int main_symbol;

/* statement/index scratch */
char saved_area;
unsigned const_magnitude;
unsigned const_value;
char const_negative;

/* fixed source/output names used by the native first-generation command */

/* scanner keyword/runtime names */

/* ass spelling fragments */

/* 6502 mnemonics used by the intentionally plain emitter */

char same_bytes(char *a, char a_length, char *b, char b_length)
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

char write_char(char value)
{
    if (compiler_error != 0) {
        return 0;
    }
    if (io_write(output_handle, value) != 0) {
        compiler_error = 7;
        return 0;
    }
    return 1;
}

char write_text(char *text)
{
    char i;

    i = 0;
    while (text[i] != 0) {
        if (write_char(text[i]) == 0) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

char write_hex_digit(char value)
{
    if (value < 10) {
        return write_char('0' + value);
    }
    return write_char('a' + value - 10);
}

char write_hex_byte(char value)
{
    char high;
    char low;

    high = (value >> 4) & 15;
    low = value & 15;
    if (write_hex_digit(high) == 0) {
        return 0;
    }
    return write_hex_digit(low);
}

char write_hex_word(unsigned value)
{
    if (write_hex_byte((value >> 8) & 255) == 0) {
        return 0;
    }
    return write_hex_byte(value & 255);
}

char write_newline()
{
    return write_char(10);
}

char emit_instruction(char *op)
{
    if (write_char(9) == 0) {
        return 0;
    }
    return write_text(op);
}

char emit_zero(char *op)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    return write_newline();
}

char emit_immediate(char *op, char value)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (write_char('#') == 0) {
        return 0;
    }
    if (write_char('$') == 0) {
        return 0;
    }
    if (write_hex_byte(value) == 0) {
        return 0;
    }
    return write_newline();
}

char emit_scratch(char *op, char *name, char high)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (write_text(name) == 0) {
        return 0;
    }
    if (high != 0) {
        if (write_text((fixed_text + 584)) == 0) {
            return 0;
        }
    }
    return write_newline();
}

char emit_global_name(char symbol)
{
    if (write_text((fixed_text + 679)) == 0) {
        return 0;
    }
    return write_hex_byte(symbol);
}

char emit_function_name(char symbol)
{
    if (write_text((fixed_text + 675)) == 0) {
        return 0;
    }
    return write_hex_byte(symbol);
}

char emit_current_name(char function_id, char slot)
{
    if (write_text((fixed_text + 683)) == 0) {
        return 0;
    }
    if (write_hex_byte(function_id) == 0) {
        return 0;
    }
    if (write_char('_') == 0) {
        return 0;
    }
    return write_hex_byte(slot);
}

char emit_symbol_name(char area, char symbol)
{
    if (area == 2) {
        return emit_current_name(current_func, symbol);
    }
    return emit_global_name(symbol);
}

char emit_symbol_operand(char *op, char area, char symbol, char high)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (emit_symbol_name(area, symbol) == 0) {
        return 0;
    }
    if (high != 0) {
        if (write_text((fixed_text + 584)) == 0) {
            return 0;
        }
    }
    return write_newline();
}

char emit_label_name(unsigned label)
{
    if (write_text((fixed_text + 587)) == 0) {
        return 0;
    }
    return write_hex_word(label);
}

char emit_label(unsigned label)
{
    if (emit_label_name(label) == 0) {
        return 0;
    }
    if (write_char(':') == 0) {
        return 0;
    }
    return write_newline();
}

char emit_jump_label(char *op, unsigned label)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (emit_label_name(label) == 0) {
        return 0;
    }
    return write_newline();
}

char emit_text_operand(char *op, char *text)
{
    if (emit_instruction(op) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (write_text(text) == 0) {
        return 0;
    }
    return write_newline();
}

char emit_include(char *path)
{
    if (write_char(9) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 182)) == 0) {
        return 0;
    }
    if (write_char('"') == 0) {
        return 0;
    }
    if (write_text(path) == 0) {
        return 0;
    }
    if (write_char('"') == 0) {
        return 0;
    }
    return write_newline();
}

char emit_byte_data(char value)
{
    if (write_char(9) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 687)) == 0) {
        return 0;
    }
    if (write_hex_byte(value) == 0) {
        return 0;
    }
    return write_newline();
}

char next_source_char()
{
    int value;
    int next;

    /* Held bytes must pass through the same CR/LF conversion as new input. */
    if (hold_valid != 0) {
        value = source_hold;
        hold_valid = 0;
    } else {
        value = io_read(source_handle);
    }
    if (value == -2) {
        compiler_error = 1;
        source_char = -1;
        return 0;
    }
    if (value == -1) {
        source_char = -1;
        return 1;
    }
    if (value == 13) {
        next = io_read(source_handle);
        if (next == -2) {
            compiler_error = 1;
            source_char = -1;
            return 0;
        }
        if (next >= 0) {
            if (next != 10) {
                source_hold = next;
                hold_valid = 1;
            }
        }
        source_char = 10;
        return 1;
    }
    source_char = value;
    return 1;
}

char step_source()
{
    if (source_char == 10) {
        source_line = source_line + 1;
    }
    return next_source_char();
}

char is_letter(int c)
{
    if (c >= 'a') {
        if (c <= 'z') {
            return 1;
        }
    }
    if (c >= 'A') {
        if (c <= 'Z') {
            return 1;
        }
    }
    if (c == '_') {
        return 1;
    }
    return 0;
}

char is_digit(int c)
{
    if (c < '0') {
        return 0;
    }
    if (c > '9') {
        return 0;
    }
    return 1;
}

int hex_value(int c)
{
    if (c >= '0') {
        if (c <= '9') {
            return c - '0';
        }
    }
    if (c >= 'a') {
        if (c <= 'f') {
            return c - 'a' + 10;
        }
    }
    if (c >= 'A') {
        if (c <= 'F') {
            return c - 'A' + 10;
        }
    }
    return -1;
}

char scan_error()
{
    compiler_error = 2;
    token_kind = 129;
    return 0;
}

char classify_identifier()
{
    int i;
    int text_offset;
    int length;

    i = 1072;
    while (fixed_text[i + 1] != 0) {
        text_offset = fixed_text[i];
        length = fixed_text[i + 1];
        if (same_bytes(token_text, token_length, (fixed_text + text_offset), length) != 0) {
            return 134 + ((i - 1072) >> 1);
        }
        i = i + 2;
    }
    return 130;
}

char skip_layout()
{
    char done;
    char comment_done;

    done = 0;
    while (done == 0) {
        while (source_char == ' ' | source_char == 9 | source_char == 10) {
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
        }
        if (source_char != '/') {
            done = 1;
        } else {
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
            if (source_char != '*') {
                return scan_error();
            }
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
            comment_done = 0;
            while (comment_done == 0) {
                if (source_char < 0) {
                    return scan_error();
                }
                if (source_char == '*') {
                    if (step_source() == 0) {
                        token_kind = 129;
                        return 0;
                    }
                    if (source_char == '/') {
                        if (step_source() == 0) {
                            token_kind = 129;
                            return 0;
                        }
                        comment_done = 1;
                    }
                } else {
                    if (step_source() == 0) {
                        token_kind = 129;
                        return 0;
                    }
                }
            }
        }
    }
    return 1;
}

char scan_identifier_token()
{
    while (is_letter(source_char) != 0 | is_digit(source_char) != 0) {
        if (token_length >= 31) {
            return scan_error();
        }
        token_text[token_length] = source_char;
        token_length = token_length + 1;
        if (step_source() == 0) {
            token_kind = 129;
            return 0;
        }
    }
    token_text[token_length] = 0;
    token_kind = classify_identifier();
    return 1;
}

char scan_number_token()
{
    int value;
    int digit;
    char base;

    base = 10;
    value = 0;
    if (source_char == '0') {
        if (step_source() == 0) {
            token_kind = 129;
            return 0;
        }
        if (source_char == 'x' | source_char == 'X') {
            base = 16;
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
            digit = hex_value(source_char);
            if (digit < 0) {
                return scan_error();
            }
        }
    }
    if (base == 10) {
        while (is_digit(source_char) != 0) {
            digit = source_char - '0';
            if (value > 6553) {
                return scan_error();
            }
            if (value == 6553) {
                if (digit > 5) {
                    return scan_error();
                }
            }
            value = value * 10 + digit;
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
        }
    } else {
        digit = hex_value(source_char);
        while (digit >= 0) {
            if (value > 4095) {
                return scan_error();
            }
            value = (value << 4) + digit;
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
            digit = hex_value(source_char);
        }
    }
    token_value = value;
    if (token_value > 32767) {
        token_type = 3;
    } else {
        token_type = 2;
    }
    token_kind = 131;
    return 1;
}

char scan_character_token()
{
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    if (source_char < 0 | source_char == 39 | source_char == 10) {
        return scan_error();
    }
    token_value = source_char;
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    if (source_char != 39) {
        return scan_error();
    }
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    token_type = 2;
    token_kind = 132;
    return 1;
}

char scan_string_token()
{
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    while (source_char != 34) {
        if (source_char < 0 | source_char == 10) {
            return scan_error();
        }
        if (token_length >= 190) {
            return scan_error();
        }
        token_text[token_length] = source_char;
        token_length = token_length + 1;
        if (step_source() == 0) {
            token_kind = 129;
            return 0;
        }
    }
    token_text[token_length] = 0;
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    token_kind = 133;
    return 1;
}

char scan_operator_token()
{
    int value;
    int table;

    value = source_char;
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    table = 1090;
    while (fixed_text[table] != 0) {
        if (value == fixed_text[table]) {
            if (source_char == fixed_text[table + 1]) {
                token_kind = fixed_text[table + 2];
                if (step_source() == 0) {
                    token_kind = 129;
                    return 0;
                }
                return 1;
            }
        }
        table = table + 3;
    }
    if (value == '!') {
        return scan_error();
    }
    token_kind = value;
    return 1;
}

char scan_token()
{
    token_length = 0;
    token_value = 0;
    token_type = 0;
    if (skip_layout() == 0) {
        return 0;
    }
    if (source_char < 0) {
        token_kind = 128;
        return 1;
    }
    if (is_letter(source_char) != 0) {
        return scan_identifier_token();
    }
    if (is_digit(source_char) != 0) {
        return scan_number_token();
    }
    if (source_char == 39) {
        return scan_character_token();
    }
    if (source_char == 34) {
        return scan_string_token();
    }
    return scan_operator_token();
}

char save_token_name()
{
    char i;

    if (token_length > 31) {
        compiler_error = 41;
        return 0;
    }
    pending_length = token_length;
    i = 0;
    while (i < token_length) {
        pending_name[i] = token_text[i];
        i = i + 1;
    }
    pending_name[i] = 0;
    return 1;
}

char find_global()
{
    char symbol;
    char i;
    int base;
    char match;

    symbol = 0;
    while (symbol < global_count) {
        if (global_name_len[symbol] == token_length) {
            base = symbol * 32;
            i = 0;
            match = 1;
            while (i < token_length) {
                if (global_name[base + i] != token_text[i]) {
                    match = 0;
                    break;
                }
                i = i + 1;
            }
            if (match != 0) {
                return symbol;
            }
        }
        symbol = symbol + 1;
    }
    return 255;
}

char find_current()
{
    char symbol;
    char i;
    int base;
    char match;

    symbol = 0;
    while (symbol < local_count) {
        if (local_name_len[symbol] == token_length) {
            base = symbol * 32;
            i = 0;
            match = 1;
            while (i < token_length) {
                if (local_name[base + i] != token_text[i]) {
                    match = 0;
                    break;
                }
                i = i + 1;
            }
            if (match != 0) {
                return symbol;
            }
        }
        symbol = symbol + 1;
    }
    return 255;
}

char lookup_name()
{
    char id;

    id = find_current();
    if (id != 255) {
        saved_area = 2;
        return id;
    }
    id = find_global();
    if (id != 255) {
        saved_area = 1;
        return id;
    }
    return 255;
}

char copy_pending_global(char symbol)
{
    char i;
    int base;

    base = symbol * 32;
    i = 0;
    while (i < pending_length) {
        global_name[base + i] = pending_name[i];
        i = i + 1;
    }
    global_name[base + i] = 0;
    global_name_len[symbol] = pending_length;
    return 1;
}

char copy_pending_local(char symbol)
{
    char i;
    int base;

    base = symbol * 32;
    i = 0;
    while (i < pending_length) {
        local_name[base + i] = pending_name[i];
        i = i + 1;
    }
    local_name[base + i] = 0;
    local_name_len[symbol] = pending_length;
    return 1;
}

int add_global_saved(char kind, char type)
{
    int id;

    if (global_count >= 176) {
        compiler_error = 6;
        return -1;
    }
    id = global_count;
    global_count = global_count + 1;
    copy_pending_global(id);
    global_kind[id] = kind;
    global_type[id] = type;
    global_array_len[id] = 0;
    global_param_start[id] = 0;
    global_param_count[id] = 0;
    return id;
}

int add_current_saved(char type)
{
    int id;

    if (local_count >= 32) {
        compiler_error = 6;
        return -1;
    }
    id = local_count;
    local_count = local_count + 1;
    copy_pending_local(id);
    local_type[id] = type;
    return id;
}

char set_pending_text(char *text, char length)
{
    char i;

    pending_length = length;
    i = 0;
    while (i < length) {
        pending_name[i] = text[i];
        i = i + 1;
    }
    pending_name[i] = 0;
    return 1;
}

char add_builtin(char *name, char length, char count, char type0, char type1)
{
    int id;

    set_pending_text(name, length);
    id = add_global_saved(4, 2);
    if (id < 0) {
        return 0;
    }
    global_param_start[id] = param_count;
    global_param_count[id] = count;
    if (count > 0) {
        param_type[param_count] = type0;
        param_count = param_count + 1;
    }
    if (count > 1) {
        param_type[param_count] = type1;
        param_count = param_count + 1;
    }
    return 1;
}

char init_symbols()
{
    global_count = 0;
    local_count = 0;
    param_count = 0;
    if (add_builtin((fixed_text + 76), 7, 2, 4, 2) == 0) {
        return 0;
    }
    if (add_builtin((fixed_text + 84), 7, 1, 2, 0) == 0) {
        return 0;
    }
    if (add_builtin((fixed_text + 92), 9, 2, 4, 2) == 0) {
        return 0;
    }
    if (add_builtin((fixed_text + 102), 8, 2, 2, 2) == 0) {
        return 0;
    }
    if (add_builtin((fixed_text + 111), 8, 1, 2, 0) == 0) {
        return 0;
    }
    return 1;
}

char type_size(char type)
{
    if (type == 1) {
        return 1;
    }
    return 2;
}

char emit_bss_assignment(char area, char symbol, unsigned size)
{
    unsigned new_end;

    /* Subtract first: a 16-bit addition can wrap before the limit check. */
    if (size > 34304 - bss_offset) {
        compiler_error = 6;
        return 0;
    }
    new_end = bss_offset + size;
    if (area == 2) {
        if (emit_current_name(current_func, symbol) == 0) {
            return 0;
        }
    } else {
        if (emit_global_name(symbol) == 0) {
            return 0;
        }
    }
    if (write_text((fixed_text + 572)) == 0) {
        return 0;
    }
    if (write_hex_word(bss_offset) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    bss_offset = new_end;
    return 1;
}

char runtime_param_name(char function_id, char argument)
{
    if (function_id == 0) {
        if (write_text((fixed_text + 626)) == 0) {
            return 0;
        }
    } else {
        if (function_id == 1) {
            if (write_text((fixed_text + 642)) == 0) {
                return 0;
            }
        } else {
            if (function_id == 2) {
                if (write_text((fixed_text + 608)) == 0) {
                    return 0;
                }
            } else {
                if (function_id == 3) {
                    if (write_text((fixed_text + 658)) == 0) {
                        return 0;
                    }
                } else {
                    if (write_text((fixed_text + 591)) == 0) {
                        return 0;
                    }
                }
            }
        }
    }
    return write_hex_digit(argument);
}

char callee_name(char function_id)
{
    if (global_kind[function_id] == 4) {
        if (function_id == 0) {
            return write_text((fixed_text + 248));
        }
        if (function_id == 1) {
            return write_text((fixed_text + 260));
        }
        if (function_id == 2) {
            return write_text((fixed_text + 272));
        }
        if (function_id == 3) {
            return write_text((fixed_text + 286));
        }
        return write_text((fixed_text + 299));
    }
    return emit_function_name(function_id);
}

char emit_callee_call(char function_id)
{
    if (emit_instruction((fixed_text + 535)) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (callee_name(function_id) == 0) {
        return 0;
    }
    return write_newline();
}

/* The same target slot may need its low and high bytes stored. */
char emit_param_byte(char function_id, char argument, char high)
{
    if (emit_instruction((fixed_text + 443)) == 0) {
        return 0;
    }
    if (write_char(' ') == 0) {
        return 0;
    }
    if (global_kind[function_id] == 4) {
        if (runtime_param_name(function_id, argument) == 0) {
            return 0;
        }
    } else {
        if (emit_current_name(function_id, argument) == 0) {
            return 0;
        }
    }
    if (high != 0) {
        if (write_text((fixed_text + 584)) == 0) {
            return 0;
        }
    }
    return write_newline();
}

char emit_param_store(char function_id, char argument, char type)
{
    if (emit_zero((fixed_text + 455)) == 0) {
        return 0;
    }
    if (type != 1) {
        if (emit_param_byte(function_id, argument, 1) == 0) {
            return 0;
        }
    }
    if (emit_zero((fixed_text + 455)) == 0) {
        return 0;
    }
    return emit_param_byte(function_id, argument, 0);
}

char emit_push_ax()
{
    return write_text((fixed_text + 694));
}

/* Materialise the last value only when another value needs A/X. */
char flush_ax()
{
    if (ax_pending == 0) {
        return 1;
    }
    ax_pending = 0;
    return emit_push_ax();
}

char hold_ax()
{
    ax_pending = 1;
    return 1;
}

char emit_pop_ax()
{
    if (ax_pending != 0) {
        ax_pending = 0;
        return 1;
    }
    return write_text((fixed_text + 710));
}

char emit_load_symbol(char area, char symbol, char type)
{
    if (emit_symbol_operand((fixed_text + 431), area, symbol, 0) == 0) {
        return 0;
    }
    if (type == 1) {
        if (emit_immediate((fixed_text + 435), 0) == 0) {
            return 0;
        }
    } else {
        if (emit_symbol_operand((fixed_text + 435), area, symbol, 1) == 0) {
            return 0;
        }
    }
    return hold_ax();
}

/* Both a global array and a string literal are constant 16-bit addresses. */
char emit_address_value(char kind, unsigned target)
{
    char high;
    char *op;
    char *prefix;

    high = 0;
    while (high < 2) {
        if (high == 0) {
            op = fixed_text + 431;
            prefix = fixed_text + 547;
        } else {
            op = fixed_text + 435;
            prefix = fixed_text + 551;
        }
        if (emit_instruction(op) == 0) {
            return 0;
        }
        if (write_text(prefix) == 0) {
            return 0;
        }
        if (kind == 2) {
            if (emit_global_name(target) == 0) {
                return 0;
            }
        } else {
            if (emit_label_name(target) == 0) {
                return 0;
            }
        }
        if (write_newline() == 0) {
            return 0;
        }
        high = high + 1;
    }
    return hold_ax();
}

char emit_array_address(char symbol)
{
    return emit_address_value(2, symbol);
}

char emit_literal_value(unsigned value)
{
    if (emit_immediate((fixed_text + 431), value & 255) == 0) {
        return 0;
    }
    if (emit_immediate((fixed_text + 435), (value >> 8) & 255) == 0) {
        return 0;
    }
    return hold_ax();
}

char emit_string_literal()
{
    unsigned data_label;
    unsigned skip_label;
    char i;

    data_label = label_counter;
    label_counter = label_counter + 1;
    skip_label = label_counter;
    label_counter = label_counter + 1;
    if (emit_jump_label((fixed_text + 531), skip_label) == 0) {
        return 0;
    }
    if (emit_label(data_label) == 0) {
        return 0;
    }
    i = 0;
    while (i < token_length) {
        if (emit_byte_data(token_text[i]) == 0) {
            return 0;
        }
        i = i + 1;
    }
    if (emit_byte_data(0) == 0) {
        return 0;
    }
    if (emit_label(skip_label) == 0) {
        return 0;
    }
    return emit_address_value(1, data_label);
}

char is_numeric_type(char type)
{
    if (type >= 1 & type <= 3) {
        return 1;
    }
    return 0;
}

char compatible_type(char actual, char expected)
{
    if (expected == 4) {
        if (actual == 4) {
            return 1;
        }
        return 0;
    }
    if (is_numeric_type(actual) != 0 & is_numeric_type(expected) != 0) {
        return 1;
    }
    return 0;
}

char operator_precedence(char op)
{
    if (op == '|') {
        return 1;
    }
    if (op == '&') {
        return 2;
    }
    if (op == 142 | op == 143) {
        return 3;
    }
    if (op == '<' | op == '>' | op == 144 | op == 145) {
        return 4;
    }
    if (op == 146 | op == 147) {
        return 5;
    }
    if (op == '+' | op == '-') {
        return 6;
    }
    if (op == '*') {
        return 7;
    }
    if (op == 200) {
        return 8;
    }
    return 0;
}

int is_binary_operator(int op)
{
    if (operator_precedence(op) > 0) {
        if (op != 200) {
            return 1;
        }
    }
    return 0;
}

char push_operator(char code, char aux, char area, char base)
{
    if (op_top >= 32) {
        compiler_error = 6;
        return 0;
    }
    op_code[op_top] = code;
    op_aux[op_top] = aux;
    op_area[op_top] = area;
    op_argc[op_top] = 0;
    op_base[op_top] = base;
    op_top = op_top + 1;
    return 1;
}

char push_value_type(char type)
{
    if (value_top >= 32) {
        compiler_error = 6;
        return 0;
    }
    value_type[value_top] = type;
    value_top = value_top + 1;
    return 1;
}

char emit_binary_prelude()
{
    return write_text((fixed_text + 726));
}

char emit_add_sub(char op)
{
    if (op == '+') {
        return write_text((fixed_text + 778));
    }
    return write_text((fixed_text + 830));
}

char emit_bitwise(char op)
{
    if (op == '&') {
        return write_text((fixed_text + 882));
    }
    return write_text((fixed_text + 929));
}

char emit_shift(char op)
{
    unsigned loop_label;
    unsigned done_label;

    loop_label = label_counter;
    label_counter = label_counter + 1;
    done_label = label_counter;
    label_counter = label_counter + 1;
    if (write_text((fixed_text + 1111)) == 0) {
        return 0;
    }
    if (emit_jump_label((fixed_text + 523), done_label) == 0) {
        return 0;
    }
    if (emit_label(loop_label) == 0) {
        return 0;
    }
    if (op == 146) {
        if (write_text((fixed_text + 1124)) == 0) {
            return 0;
        }
    } else {
        if (write_text((fixed_text + 1173)) == 0) {
            return 0;
        }
    }
    if (write_text((fixed_text + 1222)) == 0) {
        return 0;
    }
    if (emit_jump_label((fixed_text + 527), loop_label) == 0) {
        return 0;
    }
    return emit_label(done_label);
}

/*
 * The relational helper names are eight consecutive 11-byte strings in
 * fixed_text: unsigned LT/LE/GT/GE, then signed LT/LE/GT/GE.
 */
char emit_compare(char op, char unsigned_compare)
{
    unsigned offset;

    if (op == 142) {
        offset = 312;
    } else {
        if (op == 143) {
            offset = 322;
        } else {
            offset = 332;
            if (unsigned_compare == 0) {
                offset = 376;
            }
            if (op == 144) {
                offset = offset + 11;
            }
            if (op == '>') {
                offset = offset + 22;
            }
            if (op == 145) {
                offset = offset + 33;
            }
        }
    }
    return emit_text_operand((fixed_text + 535), fixed_text + offset);
}

char reduce_unary()
{
    char type;

    if (value_top < 1) {
        compiler_error = 3;
        return 0;
    }
    type = value_type[value_top - 1];
    if (is_numeric_type(type) == 0) {
        compiler_error = 5;
        return 0;
    }
    if (flush_ax() == 0) {
        return 0;
    }
    if (write_text((fixed_text + 976)) == 0) {
        return 0;
    }
    if (type == 1) {
        value_type[value_top - 1] = 2;
    }
    return 1;
}

char reduce_binary(char op)
{
    char left;
    char right;
    char result;
    char unsigned_compare;

    if (value_top < 2) {
        compiler_error = 3;
        return 0;
    }
    right = value_type[value_top - 1];
    left = value_type[value_top - 2];
    if (op == '+') {
        if (left == 4) {
            if (is_numeric_type(right) == 0) {
                compiler_error = 5;
                return 0;
            }
            result = 4;
        } else {
            if (is_numeric_type(left) == 0 | is_numeric_type(right) == 0) {
                compiler_error = 5;
                return 0;
            }
            if (left == 3 | right == 3) {
                result = 3;
            } else {
                result = 2;
            }
        }
    } else {
        if (is_numeric_type(left) == 0 | is_numeric_type(right) == 0) {
            compiler_error = 5;
            return 0;
        }
        if (left == 3 | right == 3) {
            result = 3;
        } else {
            result = 2;
        }
    }
    if (op == 146 | op == 147) {
        if (left == 3) {
            result = 3;
        } else {
            result = 2;
        }
    }
    if (flush_ax() == 0) {
        return 0;
    }
    if (emit_binary_prelude() == 0) {
        return 0;
    }
    if (op == '+' | op == '-') {
        if (emit_add_sub(op) == 0) {
            return 0;
        }
    } else {
        if (op == '&' | op == '|') {
            if (emit_bitwise(op) == 0) {
                return 0;
            }
        } else {
            if (op == '*') {
                if (emit_text_operand((fixed_text + 535), (fixed_text + 420)) == 0) {
                    return 0;
                }
            } else {
                if (op == 146 | op == 147) {
                    if (emit_shift(op) == 0) {
                        return 0;
                    }
                } else {
                    unsigned_compare = 0;
                    if (left == 3 | right == 3) {
                        unsigned_compare = 1;
                    }
                    if (emit_compare(op, unsigned_compare) == 0) {
                        return 0;
                    }
                    result = 2;
                }
            }
        }
    }
    if (hold_ax() == 0) {
        return 0;
    }
    value_top = value_top - 1;
    value_type[value_top - 1] = result;
    return 1;
}

char reduce_top_operator()
{
    char op;

    if (op_top == 0) {
        compiler_error = 3;
        return 0;
    }
    op = op_code[op_top - 1];
    op_top = op_top - 1;
    if (op == 200) {
        return reduce_unary();
    }
    return reduce_binary(op);
}

char reduce_to_marker(char marker)
{
    while (op_top > 0) {
        if (op_code[op_top - 1] == marker) {
            return 1;
        }
        if (op_code[op_top - 1] >= 201) {
            compiler_error = 3;
            return 0;
        }
        if (reduce_top_operator() == 0) {
            return 0;
        }
    }
    compiler_error = 3;
    return 0;
}

char emit_call_finish(char marker_index)
{
    char function_id;
    char argc;
    char base;
    char i;
    char expected;
    char actual;

    function_id = op_aux[marker_index];
    argc = op_argc[marker_index];
    base = op_base[marker_index];
    if (argc != global_param_count[function_id]) {
        compiler_error = 5;
        return 0;
    }
    i = 0;
    while (i < argc) {
        actual = value_type[base + i];
        expected = param_type[global_param_start[function_id] + i];
        if (compatible_type(actual, expected) == 0) {
            compiler_error = 5;
            return 0;
        }
        i = i + 1;
    }
    if (flush_ax() == 0) {
        return 0;
    }
    i = argc;
    while (i > 0) {
        i = i - 1;
        expected = param_type[global_param_start[function_id] + i];
        if (emit_param_store(function_id, i, expected) == 0) {
            return 0;
        }
    }
    if (emit_callee_call(function_id) == 0) {
        return 0;
    }
    value_top = base;
    if (global_type[function_id] == 1) {
        if (emit_immediate((fixed_text + 435), 0) == 0) {
            return 0;
        }
    }
    if (hold_ax() == 0) {
        return 0;
    }
    return push_value_type(global_type[function_id]);
}

char emit_index_address(char area, char symbol, char kind, char element_type)
{
    if (emit_pop_ax() == 0) {
        return 0;
    }
    if (kind == 2) {
        if (element_type != 1) {
            if (write_text((fixed_text + 1629)) == 0) {
                return 0;
            }
        }
        if (write_text((fixed_text + 1674)) == 0) {
            return 0;
        }
        if (emit_global_name(symbol) == 0) {
            return 0;
        }
        if (write_text((fixed_text + 1687)) == 0) {
            return 0;
        }
        if (emit_global_name(symbol) == 0) {
            return 0;
        }
        return write_text((fixed_text + 1713));
    }
    if (write_text((fixed_text + 1729)) == 0) {
        return 0;
    }
    if (emit_symbol_name(area, symbol) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 1740)) == 0) {
        return 0;
    }
    if (emit_symbol_name(area, symbol) == 0) {
        return 0;
    }
    return write_text((fixed_text + 1764));
}

char emit_index_load(char area, char symbol, char kind, char element_type)
{
    if (emit_index_address(area, symbol, kind, element_type) == 0) {
        return 0;
    }
    if (element_type == 1) {
        return write_text((fixed_text + 1228));
    }
    return write_text((fixed_text + 1280));
}

char finish_call_marker()
{
    int marker;
    char base;

    marker = op_top - 1;
    base = op_base[marker];
    if (value_top == base) {
        if (op_argc[marker] != 0) {
            compiler_error = 3;
            return 0;
        }
    } else {
        if (value_top != base + op_argc[marker] + 1) {
            compiler_error = 3;
            return 0;
        }
        op_argc[marker] = op_argc[marker] + 1;
    }
    if (emit_call_finish(marker) == 0) {
        return 0;
    }
    op_top = op_top - 1;
    return 1;
}

char expression_identifier()
{
    char id;
    char area;
    char kind;
    char type;

    id = lookup_name();
    if (id == 255) {
        compiler_error = 42;
        return 0;
    }
    area = saved_area;
    if (area == 2) {
        kind = 1;
        type = local_type[id];
    } else {
        kind = global_kind[id];
        type = global_type[id];
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind == '(') {
        if (area != 1) {
            compiler_error = 5;
            return 0;
        }
        if (kind != 3 & kind != 4) {
            compiler_error = 5;
            return 0;
        }
        if (push_operator(202, id, area, value_top) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (token_kind == '[') {
        if (kind != 2 & type != 4) {
            compiler_error = 5;
            return 0;
        }
        if (push_operator(203, id, area, value_top) == 0) {
            return 0;
        }
        op_argc[op_top - 1] = kind;
        return scan_token();
    }
    if (kind == 2) {
        if (type != 1) {
            compiler_error = 5;
            return 0;
        }
        if (emit_array_address(id) == 0) {
            return 0;
        }
        if (push_value_type(4) == 0) {
            return 0;
        }
    } else {
        if (kind != 1) {
            compiler_error = 5;
            return 0;
        }
        if (emit_load_symbol(area, id, type) == 0) {
            return 0;
        }
        if (push_value_type(type) == 0) {
            return 0;
        }
    }
    expr_expect = 0;
    return 1;
}

char expression_value_step()
{
    char type;

    if (token_kind == '-') {
        if (push_operator(200, 0, 0, value_top) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (token_kind == '(') {
        if (push_operator(201, 0, 0, value_top) == 0) {
            return 0;
        }
        return scan_token();
    }
    /* A new value may overwrite A/X; the earlier semantic value is live. */
    if (token_kind == 131 | token_kind == 132 | token_kind == 133 | token_kind == 130) {
        if (flush_ax() == 0) {
            return 0;
        }
    }
    if (token_kind == 131 | token_kind == 132) {
        type = token_type;
        if (emit_literal_value(token_value) == 0) {
            return 0;
        }
        if (push_value_type(type) == 0) {
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        expr_expect = 0;
        return 1;
    }
    if (token_kind == 133) {
        if (emit_string_literal() == 0) {
            return 0;
        }
        if (push_value_type(4) == 0) {
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        expr_expect = 0;
        return 1;
    }
    if (token_kind == 130) {
        return expression_identifier();
    }
    if (token_kind == ')') {
        if (op_top > 0) {
            if (op_code[op_top - 1] == 202) {
                if (finish_call_marker() == 0) {
                    return 0;
                }
                if (scan_token() == 0) {
                    return 0;
                }
                expr_expect = 0;
                return 1;
            }
        }
    }
    compiler_error = 3;
    return 0;
}

char expression_close_paren()
{
    int marker;
    char found;

    marker = op_top;
    found = 0;
    while (marker > 0) {
        marker = marker - 1;
        if (op_code[marker] == 201 | op_code[marker] == 202) {
            found = 1;
            break;
        }
    }
    if (found == 0) {
        expr_done = 1;
        return 1;
    }
    while (op_top - 1 > marker) {
        if (reduce_top_operator() == 0) {
            return 0;
        }
    }
    if (op_code[marker] == 201) {
        op_top = op_top - 1;
    } else {
        if (finish_call_marker() == 0) {
            return 0;
        }
    }
    if (scan_token() == 0) {
        return 0;
    }
    expr_expect = 0;
    return 1;
}

char expression_close_index()
{
    int marker;
    char found;
    int id;
    char area;
    char kind;
    char type;

    marker = op_top;
    found = 0;
    while (marker > 0) {
        marker = marker - 1;
        if (op_code[marker] == 203) {
            found = 1;
            break;
        }
        if (op_code[marker] >= 201) {
            break;
        }
    }
    if (found == 0) {
        expr_done = 1;
        return 1;
    }
    if (reduce_to_marker(203) == 0) {
        return 0;
    }
    marker = op_top - 1;
    if (value_top != op_base[marker] + 1) {
        compiler_error = 3;
        return 0;
    }
    id = op_aux[marker];
    area = op_area[marker];
    kind = op_argc[marker];
    if (kind == 2) {
        type = global_type[id];
    } else {
        type = 1;
    }
    if (kind == 5) {
        if (flush_ax() == 0) {
            return 0;
        }
        if (write_text((fixed_text + 1782)) == 0) {
            return 0;
        }
        value_top = value_top - 1;
    } else {
        if (emit_index_load(area, id, kind, type) == 0) {
            return 0;
        }
    }
    value_type[value_top - 1] = type;
    op_top = op_top - 1;
    if (scan_token() == 0) {
        return 0;
    }
    expr_expect = 0;
    return 1;
}

char expression_operator_step()
{
    char precedence;
    char top_precedence;
    int marker;

    if (is_binary_operator(token_kind) != 0) {
        precedence = operator_precedence(token_kind);
        while (op_top > 0) {
            marker = op_code[op_top - 1];
            if (marker >= 201) {
                break;
            }
            top_precedence = operator_precedence(marker);
            if (top_precedence < precedence) {
                break;
            }
            if (reduce_top_operator() == 0) {
                return 0;
            }
        }
        if (push_operator(token_kind, 0, 0, value_top) == 0) {
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        expr_expect = 1;
        return 1;
    }
    if (token_kind == '[') {
        /* The pointer value remains stacked while its index is parsed. */
        if (value_type[value_top - 1] != 4) {
            compiler_error = 5;
            return 0;
        }
        if (push_operator(203, 0, 0, value_top) == 0) {
            return 0;
        }
        op_argc[op_top - 1] = 5;
        expr_expect = 1;
        return scan_token();
    }
    if (token_kind == ',') {
        if (reduce_to_marker(202) == 0) {
            return 0;
        }
        marker = op_top - 1;
        if (value_top != op_base[marker] + op_argc[marker] + 1) {
            compiler_error = 3;
            return 0;
        }
        op_argc[marker] = op_argc[marker] + 1;
        if (scan_token() == 0) {
            return 0;
        }
        expr_expect = 1;
        return 1;
    }
    if (token_kind == ')') {
        return expression_close_paren();
    }
    if (token_kind == ']') {
        return expression_close_index();
    }
    expr_done = 1;
    return 1;
}

char expression_loop()
{
    expr_expect = 1;
    expr_done = 0;
    while (expr_done == 0) {
        if (expr_expect != 0) {
            if (expression_value_step() == 0) {
                return 0;
            }
        } else {
            if (expression_operator_step() == 0) {
                return 0;
            }
        }
    }
    if (expr_expect != 0) {
        compiler_error = 3;
        return 0;
    }
    while (op_top > 0) {
        if (op_code[op_top - 1] >= 201) {
            break;
        }
        if (reduce_top_operator() == 0) {
            return 0;
        }
    }
    if (op_top != 0) {
        compiler_error = 3;
        return 0;
    }
    if (value_top != 1) {
        compiler_error = 3;
        return 0;
    }
    expr_type = value_type[0];
    return 1;
}

char compile_expression()
{
    op_top = 0;
    value_top = 0;
    ax_pending = 0;
    return expression_loop();
}

char compile_call_stmt(char function_id)
{
    op_top = 0;
    value_top = 0;
    if (push_operator(202, function_id, 1, 0) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (expression_loop() == 0) {
        return 0;
    }
    if (ax_pending != 0) {
        ax_pending = 0;
        return 1;
    }
    if (emit_zero((fixed_text + 455)) == 0) {
        return 0;
    }
    return emit_zero((fixed_text + 455));
}

char emit_false_jump(unsigned target)
{
    unsigned skip;

    skip = label_counter;
    label_counter = label_counter + 1;
    if (emit_pop_ax() == 0) {
        return 0;
    }
    if (emit_scratch((fixed_text + 443), (fixed_text + 198), 0) == 0) {
        return 0;
    }
    if (emit_zero((fixed_text + 459)) == 0) {
        return 0;
    }
    if (emit_scratch((fixed_text + 495), (fixed_text + 198), 0) == 0) {
        return 0;
    }
    if (emit_jump_label((fixed_text + 527), skip) == 0) {
        return 0;
    }
    if (emit_jump_label((fixed_text + 531), target) == 0) {
        return 0;
    }
    return emit_label(skip);
}

char emit_scalar_store(char area, char symbol, char type)
{
    if (emit_pop_ax() == 0) {
        return 0;
    }
    if (emit_symbol_operand((fixed_text + 443), area, symbol, 0) == 0) {
        return 0;
    }
    if (type != 1) {
        if (emit_symbol_operand((fixed_text + 447), area, symbol, 1) == 0) {
            return 0;
        }
    }
    return 1;
}

char emit_index_store(char element_type)
{
    if (flush_ax() == 0) {
        return 0;
    }
    if (element_type == 1) {
        return write_text((fixed_text + 1372));
    }
    return write_text((fixed_text + 1483));
}

int find_break_label()
{
    char i;

    i = ctrl_top;
    while (i > 0) {
        i = i - 1;
        if (ctrl_kind[i] == 4) {
            return ctrl_label1[i];
        }
    }
    return -1;
}

char push_control(char kind, unsigned label0, unsigned label1)
{
    if (ctrl_top >= 16) {
        compiler_error = 6;
        return 0;
    }
    ctrl_kind[ctrl_top] = kind;
    ctrl_label0[ctrl_top] = label0;
    ctrl_label1[ctrl_top] = label1;
    ctrl_top = ctrl_top + 1;
    return 1;
}

char statement_close()
{
    char frame;
    char kind;
    unsigned second_label;

    if (ctrl_top == 0) {
        if (scan_token() == 0) {
            return 0;
        }
        return 2;
    }
    frame = ctrl_top - 1;
    kind = ctrl_kind[frame];
    if (kind == 1) {
        ctrl_top = ctrl_top - 1;
        return scan_token();
    }
    if (kind == 4) {
        if (emit_jump_label((fixed_text + 531), ctrl_label0[frame]) == 0) {
            return 0;
        }
        if (emit_label(ctrl_label1[frame]) == 0) {
            return 0;
        }
        ctrl_top = ctrl_top - 1;
        return scan_token();
    }
    if (kind == 3) {
        if (emit_label(ctrl_label1[frame]) == 0) {
            return 0;
        }
        ctrl_top = ctrl_top - 1;
        return scan_token();
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != 138) {
        if (emit_label(ctrl_label0[frame]) == 0) {
            return 0;
        }
        ctrl_top = ctrl_top - 1;
        return 1;
    }
    second_label = label_counter;
    label_counter = label_counter + 1;
    if (emit_jump_label((fixed_text + 531), second_label) == 0) {
        return 0;
    }
    if (emit_label(ctrl_label0[frame]) == 0) {
        return 0;
    }
    ctrl_kind[frame] = 3;
    ctrl_label1[frame] = second_label;
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '{') {
        compiler_error = 3;
        return 0;
    }
    return scan_token();
}

char statement_if()
{
    unsigned false_label;

    false_label = label_counter;
    label_counter = label_counter + 1;
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '(') {
        compiler_error = 3;
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (compile_expression() == 0) {
        return 0;
    }
    if (token_kind != ')') {
        compiler_error = 3;
        return 0;
    }
    if (emit_false_jump(false_label) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '{') {
        compiler_error = 3;
        return 0;
    }
    if (push_control(2, false_label, 0) == 0) {
        return 0;
    }
    return scan_token();
}

char statement_while()
{
    unsigned loop_label;
    unsigned done_label;

    loop_label = label_counter;
    label_counter = label_counter + 1;
    done_label = label_counter;
    label_counter = label_counter + 1;
    if (emit_label(loop_label) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '(') {
        compiler_error = 3;
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (compile_expression() == 0) {
        return 0;
    }
    if (token_kind != ')') {
        compiler_error = 3;
        return 0;
    }
    if (emit_false_jump(done_label) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '{') {
        compiler_error = 3;
        return 0;
    }
    if (push_control(4, loop_label, done_label) == 0) {
        return 0;
    }
    return scan_token();
}

char statement_identifier()
{
    char id;
    char area;
    char kind;
    char type;

    id = lookup_name();
    if (id == 255) {
        compiler_error = 43;
        return 0;
    }
    area = saved_area;
    if (area == 2) {
        kind = 1;
        type = local_type[id];
    } else {
        kind = global_kind[id];
        type = global_type[id];
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind == '=') {
        if (kind != 1) {
            compiler_error = 5;
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (compile_expression() == 0) {
            return 0;
        }
        if (type == 4) {
            if (expr_type != 4) {
                compiler_error = 5;
                return 0;
            }
        } else {
            if (is_numeric_type(expr_type) == 0) {
                compiler_error = 5;
                return 0;
            }
        }
        if (token_kind != ';') {
            compiler_error = 3;
            return 0;
        }
        if (emit_scalar_store(area, id, type) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (token_kind == '[') {
        if (kind != 2 & type != 4) {
            compiler_error = 5;
            return 0;
        }
        if (kind != 2) {
            type = 1;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (compile_expression() == 0) {
            return 0;
        }
        if (token_kind != ']') {
            compiler_error = 3;
            return 0;
        }
        if (emit_index_address(area, id, kind, type) == 0) {
            return 0;
        }
        if (emit_scratch((fixed_text + 431), (fixed_text + 205), 0) == 0) {
            return 0;
        }
        if (emit_scratch((fixed_text + 435), (fixed_text + 205), 1) == 0) {
            return 0;
        }
        if (emit_push_ax() == 0) {
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (token_kind != '=') {
            compiler_error = 3;
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (compile_expression() == 0) {
            return 0;
        }
        if (token_kind != ';') {
            compiler_error = 3;
            return 0;
        }
        if (emit_index_store(type) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (token_kind == '(') {
        if (area != 1) {
            compiler_error = 5;
            return 0;
        }
        if (kind != 3 & kind != 4) {
            compiler_error = 5;
            return 0;
        }
        if (compile_call_stmt(id) == 0) {
            return 0;
        }
        if (token_kind != ';') {
            compiler_error = 3;
            return 0;
        }
        return scan_token();
    }
    compiler_error = 3;
    return 0;
}

char parse_statements()
{
    int break_label;
    char closed;

    ctrl_top = 0;
    while (1) {
        if (token_kind == '}') {
            closed = statement_close();
            if (closed == 0) {
                return 0;
            }
            if (closed == 2) {
                return 1;
            }
        } else {
            if (token_kind == '{') {
                if (push_control(1, 0, 0) == 0) {
                    return 0;
                }
                if (scan_token() == 0) {
                    return 0;
                }
            } else {
                if (token_kind == 137) {
                    if (statement_if() == 0) {
                        return 0;
                    }
                } else {
                    if (token_kind == 139) {
                        if (statement_while() == 0) {
                            return 0;
                        }
                    } else {
                        if (token_kind == 140) {
                            break_label = find_break_label();
                            if (break_label < 0) {
                                compiler_error = 3;
                                return 0;
                            }
                            if (emit_jump_label((fixed_text + 531), break_label) == 0) {
                                return 0;
                            }
                            if (scan_token() == 0) {
                                return 0;
                            }
                            if (token_kind != ';') {
                                compiler_error = 3;
                                return 0;
                            }
                            if (scan_token() == 0) {
                                return 0;
                            }
                        } else {
                            if (token_kind == 141) {
                                if (scan_token() == 0) {
                                    return 0;
                                }
                                if (compile_expression() == 0) {
                                    return 0;
                                }
                                if (token_kind != ';') {
                                    compiler_error = 3;
                                    return 0;
                                }
                                if (is_numeric_type(expr_type) == 0) {
                                    compiler_error = 5;
                                    return 0;
                                }
                                if (emit_pop_ax() == 0) {
                                    return 0;
                                }
                                if (emit_zero((fixed_text + 539)) == 0) {
                                    return 0;
                                }
                                if (scan_token() == 0) {
                                    return 0;
                                }
                            } else {
                                if (token_kind != 130) {
                                    compiler_error = 3;
                                    return 0;
                                }
                                if (statement_identifier() == 0) {
                                    return 0;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

char parse_type()
{
    char type;

    type = 0;
    if (token_kind == 134) {
        type = 1;
    } else {
        if (token_kind == 135) {
            type = 2;
        } else {
            if (token_kind == 136) {
                type = 3;
            }
        }
    }
    if (type == 0) {
        compiler_error = 3;
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind == '*') {
        if (type != 1) {
            compiler_error = 5;
            return 0;
        }
        type = 4;
        if (scan_token() == 0) {
            return 0;
        }
    }
    return type;
}

char parse_constant()
{
    char negative;

    negative = 0;
    if (token_kind == '-') {
        negative = 1;
        if (scan_token() == 0) {
            return 0;
        }
    }
    if (token_kind != 131 & token_kind != 132) {
        compiler_error = 3;
        return 0;
    }
    const_magnitude = token_value;
    const_negative = negative;
    const_value = token_value;
    if (negative != 0) {
        const_value = 0 - const_value;
    }
    return scan_token();
}

char constant_fits_type(char type)
{
    if (type == 1) {
        if (const_negative != 0) {
            return 0;
        }
        if (const_value > 255) {
            return 0;
        }
        return 1;
    }
    if (type == 2) {
        if (const_negative != 0) {
            if (const_magnitude > 32768) {
                return 0;
            }
            return 1;
        }
        if (const_value > 32767) {
            return 0;
        }
        return 1;
    }
    if (type == 3) {
        if (const_negative != 0) {
            return 0;
        }
        return 1;
    }
    return 0;
}

char emit_global_label(char symbol)
{
    if (emit_global_name(symbol) == 0) {
        return 0;
    }
    if (write_char(':') == 0) {
        return 0;
    }
    return write_newline();
}

char emit_typed_const(char type, unsigned value)
{
    if (type == 1) {
        return emit_byte_data(value & 255);
    }
    if (emit_byte_data(value & 255) == 0) {
        return 0;
    }
    return emit_byte_data((value >> 8) & 255);
}

char parse_global_array(char symbol, char element_type)
{
    unsigned length;
    unsigned emitted;
    char width;

    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != 131) {
        compiler_error = 3;
        return 0;
    }
    length = token_value;
    if (length == 0) {
        compiler_error = 5;
        return 0;
    }
    global_array_len[symbol] = length;
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != ']') {
        compiler_error = 3;
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    width = type_size(element_type);
    if (token_kind == ';') {
        /* Check element count before 16-bit byte multiplication can wrap. */
        if (width == 2 & length > 17152) {
            compiler_error = 6;
            return 0;
        }
        if (emit_bss_assignment(1, symbol, length * width) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (token_kind != '=') {
        compiler_error = 3;
        return 0;
    }
    if (emit_global_label(symbol) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    emitted = 0;
    if (token_kind == 133) {
        if (element_type != 1) {
            compiler_error = 5;
            return 0;
        }
        if (token_length + 1 > length) {
            compiler_error = 5;
            return 0;
        }
        while (emitted < token_length) {
            if (emit_byte_data(token_text[emitted]) == 0) {
                return 0;
            }
            emitted = emitted + 1;
        }
        if (emit_byte_data(0) == 0) {
            return 0;
        }
        emitted = emitted + 1;
        if (scan_token() == 0) {
            return 0;
        }
    } else {
        if (token_kind != '{') {
            compiler_error = 3;
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (token_kind != '}') {
            while (1) {
                if (emitted >= length) {
                    compiler_error = 5;
                    return 0;
                }
                if (parse_constant() == 0) {
                    return 0;
                }
                if (constant_fits_type(element_type) == 0) {
                    compiler_error = 5;
                    return 0;
                }
                if (emit_typed_const(element_type, const_value) == 0) {
                    return 0;
                }
                emitted = emitted + 1;
                if (token_kind == '}') {
                    break;
                }
                if (token_kind != ',') {
                    compiler_error = 3;
                    return 0;
                }
                if (scan_token() == 0) {
                    return 0;
                }
            }
        }
        if (scan_token() == 0) {
            return 0;
        }
    }
    while (emitted < length) {
        if (emit_typed_const(element_type, 0) == 0) {
            return 0;
        }
        emitted = emitted + 1;
    }
    if (token_kind != ';') {
        compiler_error = 3;
        return 0;
    }
    return scan_token();
}

char parse_global_scalar(char symbol, char type)
{
    if (token_kind == ';') {
        if (emit_bss_assignment(1, symbol, type_size(type)) == 0) {
            return 0;
        }
        return scan_token();
    }
    if (type == 4) {
        compiler_error = 5;
        return 0;
    }
    if (token_kind != '=') {
        compiler_error = 3;
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (parse_constant() == 0) {
        return 0;
    }
    if (constant_fits_type(type) == 0) {
        compiler_error = 5;
        return 0;
    }
    if (emit_global_label(symbol) == 0) {
        return 0;
    }
    if (emit_typed_const(type, const_value) == 0) {
        return 0;
    }
    if (token_kind != ';') {
        compiler_error = 3;
        return 0;
    }
    return scan_token();
}

char parse_local()
{
    char type;
    int slot;

    type = parse_type();
    if (type == 0) {
        return 0;
    }
    if (token_kind != 130) {
        compiler_error = 3;
        return 0;
    }
    if (find_current() != 255) {
        compiler_error = 44;
        return 0;
    }
    if (save_token_name() == 0) {
        return 0;
    }
    slot = local_count;
    if (emit_bss_assignment(2, slot, type_size(type)) == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind == '=') {
        if (scan_token() == 0) {
            return 0;
        }
        if (compile_expression() == 0) {
            return 0;
        }
        if (token_kind != ';') {
            compiler_error = 3;
            return 0;
        }
        if (type == 4) {
            if (expr_type != 4) {
                compiler_error = 5;
                return 0;
            }
        } else {
            if (is_numeric_type(expr_type) == 0) {
                compiler_error = 5;
                return 0;
            }
        }
        if (emit_scalar_store(2, slot, type) == 0) {
            return 0;
        }
    } else {
        if (token_kind != ';') {
            compiler_error = 3;
            return 0;
        }
    }
    if (add_current_saved(type) < 0) {
        return 0;
    }
    return scan_token();
}

char parse_function(char function_id)
{
    char type;
    int slot;
    char param_start;

    current_func = function_id;
    local_count = 0;
    param_start = param_count;
    global_param_start[function_id] = param_start;
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != ')') {
        while (1) {
            type = parse_type();
            if (type == 0) {
                return 0;
            }
            if (token_kind != 130) {
                compiler_error = 3;
                return 0;
            }
            if (find_current() != 255) {
                compiler_error = 45;
                return 0;
            }
            if (save_token_name() == 0) {
                return 0;
            }
            slot = add_current_saved(type);
            if (slot < 0) {
                return 0;
            }
            if (param_count >= 128) {
                compiler_error = 6;
                return 0;
            }
            param_type[param_count] = type;
            param_count = param_count + 1;
            global_param_count[function_id] = global_param_count[function_id] + 1;
            if (emit_bss_assignment(2, slot, type_size(type)) == 0) {
                return 0;
            }
            if (scan_token() == 0) {
                return 0;
            }
            if (token_kind == ')') {
                break;
            }
            if (token_kind != ',') {
                compiler_error = 3;
                return 0;
            }
            if (scan_token() == 0) {
                return 0;
            }
        }
    }
    if (scan_token() == 0) {
        return 0;
    }
    if (token_kind != '{') {
        compiler_error = 3;
        return 0;
    }
    if (emit_function_name(function_id) == 0) {
        return 0;
    }
    if (write_char(':') == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    if (scan_token() == 0) {
        return 0;
    }
    while (token_kind == 134 | token_kind == 135 | token_kind == 136) {
        if (parse_local() == 0) {
            return 0;
        }
    }
    if (parse_statements() == 0) {
        return 0;
    }
    local_count = 0;
    return 1;
}

char parse_unit()
{
    char type;
    int symbol;
    char functions_started;

    functions_started = 0;
    while (token_kind != 128) {
        type = parse_type();
        if (type == 0) {
            return 0;
        }
        if (token_kind != 130) {
            compiler_error = 3;
            return 0;
        }
        if (find_global() != 255) {
            compiler_error = 46;
            return 0;
        }
        if (save_token_name() == 0) {
            return 0;
        }
        if (scan_token() == 0) {
            return 0;
        }
        if (token_kind == '(') {
            if (type != 1 & type != 2) {
                compiler_error = 5;
                return 0;
            }
            functions_started = 1;
            symbol = add_global_saved(3, type);
            if (symbol < 0) {
                return 0;
            }
            if (same_bytes(pending_name, pending_length, (fixed_text + 120), 4) != 0) {
                main_symbol = symbol;
            }
            if (parse_function(symbol) == 0) {
                return 0;
            }
        } else {
            if (functions_started != 0) {
                compiler_error = 3;
                return 0;
            }
            if (token_kind == '[') {
                if (type == 4) {
                    compiler_error = 5;
                    return 0;
                }
                symbol = add_global_saved(2, type);
                if (symbol < 0) {
                    return 0;
                }
                if (parse_global_array(symbol, type) == 0) {
                    return 0;
                }
            } else {
                symbol = add_global_saved(1, type);
                if (symbol < 0) {
                    return 0;
                }
                if (parse_global_scalar(symbol, type) == 0) {
                    return 0;
                }
            }
        }
    }
    return 1;
}

char emit_finish_program()
{
    if (write_text((fixed_text + 212)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 567)) == 0) {
        return 0;
    }
    if (write_hex_word(bss_offset) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    /*
     * Runtime code may refer to __nc_bss_bytes, so emit it only after that
     * constant is known. User code can freely make forward JSR references to
     * the runtime helpers; ass already resolves those ordinary label fixups.
     */
    if (emit_include((fixed_text + 153)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 227)) == 0) {
        return 0;
    }
    if (write_char(':') == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    if (emit_text_operand((fixed_text + 535), (fixed_text + 238)) == 0) {
        return 0;
    }
    if (main_symbol >= 0) {
        if (global_param_count[main_symbol] != 0) {
            compiler_error = 5;
            return 0;
        }
        if (emit_instruction((fixed_text + 535)) == 0) {
            return 0;
        }
        if (write_char(' ') == 0) {
            return 0;
        }
        if (emit_function_name(main_symbol) == 0) {
            return 0;
        }
        if (write_newline() == 0) {
            return 0;
        }
    } else {
        if (emit_immediate((fixed_text + 431), 0) == 0) {
            return 0;
        }
        if (emit_immediate((fixed_text + 435), 0) == 0) {
            return 0;
        }
    }
    return emit_zero((fixed_text + 539));
}

char compile_file(char *source_name, char source_length, char *output_name, char output_length)
{
    compiler_error = 0;
    hold_valid = 0;
    source_line = 1;
    bss_offset = 0;
    label_counter = 1;
    main_symbol = -1;
    source_handle = io_open(source_name, source_length);
    if (source_handle < 0) {
        return 8;
    }
    output_handle = io_create(output_name, output_length);
    if (output_handle < 0) {
        io_close(source_handle);
        return 9;
    }
    if (init_symbols() == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    if (emit_include((fixed_text + 125)) == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    if (next_source_char() == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    if (scan_token() == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    if (parse_unit() == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    if (emit_finish_program() == 0) {
        io_close(source_handle);
        io_close(output_handle);
        return compiler_error;
    }
    io_close(source_handle);
    io_close(output_handle);
    return 0;
}

/*
 * Read a source pathname from BUILD/N1JOB on device 8. This small bootstrap
 * entry point leaves compile_file generic: the test selects a committed input
 * without making or compiling a private variant of nanoc1.c.
 * BUILD/N1JOB contains raw filename bytes, without a trailing newline.
 */
int main()
{
    int job;
    int value;
    char length = 0;

    job = io_open((fixed_text + 0), 11);
    if (job < 0) {
        return 8;
    }
    value = io_read(job);
    while (value >= 0 & length < 63) {
        job_source[length] = value;
        length = length + 1;
        value = io_read(job);
    }
    io_close(job);
    if (length == 0 | value != -1) {
        return 8;
    }
    return compile_file(job_source, length, (fixed_text + 21), 9);
}
