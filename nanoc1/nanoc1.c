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
 * fixed_text map (offset -> spelling).  Phase 1 has no preprocessor or const
 * declarations, so one byte pool keeps the bootstrap compiler inside nanoc0's
 * persistent-symbol/name budgets without duplicating machine-facing strings.
 * The numeric offsets used below are deliberately centralized here.  #38 should
 * treat this as concrete pressure for a small constant/naming facility.
 *
 *   0  TESTS/NANOC1/N1SRC.C
 *  21  N1OUT.ASM
 *  31  char
 *  36  int
 *  40  unsigned
 *  49  if
 *  52  else
 *  57  while
 *  63  break
 *  69  return
 *  76  io_open
 *  84  io_read
 *  92  io_create
 * 102  io_write
 * 111  io_close
 * 120  main
 * 125  ../nanoc1/target/header.asm
 * 153  ../nanoc1/target/runtime.asm
 * 182  include 
 * 191  NC_BSS
 * 198  NC_TMP
 * 205  NC_PTR
 * 212  __nc_bss_bytes
 * 227  __nc_entry
 * 238  __nc_init
 * 248  __c_io_open
 * 260  __c_io_read
 * 272  __c_io_create
 * 286  __c_io_write
 * 299  __c_io_close
 * 312  __nc_eq16
 * 322  __nc_ne16
 * 332  __nc_ult16
 * 343  __nc_ule16
 * 354  __nc_ugt16
 * 365  __nc_uge16
 * 376  __nc_slt16
 * 387  __nc_sle16
 * 398  __nc_sgt16
 * 409  __nc_sge16
 * 420  __nc_mul16
 * 431  lda
 * 435  ldx
 * 439  ldy
 * 443  sta
 * 447  stx
 * 451  pha
 * 455  pla
 * 459  txa
 * 463  tax
 * 467  tay
 * 471  tya
 * 475  clc
 * 479  sec
 * 483  adc
 * 487  sbc
 * 491  and
 * 495  ora
 * 499  asl
 * 503  rol
 * 507  lsr
 * 511  ror
 * 515  iny
 * 519  dey
 * 523  beq
 * 527  bne
 * 531  jmp
 * 535  jsr
 * 539  rts
 * 543  eor
 * 547   #<
 * 551   #>
 * 555   (NC_PTR),y
 * 567   = $
 * 572   = NC_BSS+$
 * 584  +1
 * 587  __L
 * 591  __c_io_close__v0
 * 608  __c_io_create__v0
 * 626  __c_io_open__v0
 * 642  __c_io_read__v0
 * 658  __c_io_write__v0
 * 675  __f
 * 679  __g
 * 683  __v
 * 687  byte $
 */
/* compact templates appended at offsets: push_ax=694, pop_ax=710, binary_prelude=726, add16=778, sub16=830, and16=882, or16=929, neg16=976, keyword_table=1072, two_char_operator_table=1090 */
/* more compact templates: shift_prefix=1111, shift_left=1124, shift_right=1173, shift_dec=1222, index_load_char=1228, index_load_word=1280, index_store_char=1372, index_store_word=1483, scale_index=1629, array_add_lo=1674, array_mid=1687, array_end=1713, ptr_add_lo=1729, ptr_mid=1740, ptr_high_suffix=1764 */
char fixed_text[1782] = {
    84,69,83,84,83,47,78,65,78,79,67,49,47,78,49,83,
    82,67,46,67,0,78,49,79,85,84,46,65,83,77,0,99,
    104,97,114,0,105,110,116,0,117,110,115,105,103,110,101,100,
    0,105,102,0,101,108,115,101,0,119,104,105,108,101,0,98,
    114,101,97,107,0,114,101,116,117,114,110,0,105,111,95,111,
    112,101,110,0,105,111,95,114,101,97,100,0,105,111,95,99,
    114,101,97,116,101,0,105,111,95,119,114,105,116,101,0,105,
    111,95,99,108,111,115,101,0,109,97,105,110,0,46,46,47,
    110,97,110,111,99,49,47,116,97,114,103,101,116,47,104,101,
    97,100,101,114,46,97,115,109,0,46,46,47,110,97,110,111,
    99,49,47,116,97,114,103,101,116,47,114,117,110,116,105,109,
    101,46,97,115,109,0,105,110,99,108,117,100,101,32,0,78,
    67,95,66,83,83,0,78,67,95,84,77,80,0,78,67,95,
    80,84,82,0,95,95,110,99,95,98,115,115,95,98,121,116,
    101,115,0,95,95,110,99,95,101,110,116,114,121,0,95,95,
    110,99,95,105,110,105,116,0,95,95,99,95,105,111,95,111,
    112,101,110,0,95,95,99,95,105,111,95,114,101,97,100,0,
    95,95,99,95,105,111,95,99,114,101,97,116,101,0,95,95,
    99,95,105,111,95,119,114,105,116,101,0,95,95,99,95,105,
    111,95,99,108,111,115,101,0,95,95,110,99,95,101,113,49,
    54,0,95,95,110,99,95,110,101,49,54,0,95,95,110,99,
    95,117,108,116,49,54,0,95,95,110,99,95,117,108,101,49,
    54,0,95,95,110,99,95,117,103,116,49,54,0,95,95,110,
    99,95,117,103,101,49,54,0,95,95,110,99,95,115,108,116,
    49,54,0,95,95,110,99,95,115,108,101,49,54,0,95,95,
    110,99,95,115,103,116,49,54,0,95,95,110,99,95,115,103,
    101,49,54,0,95,95,110,99,95,109,117,108,49,54,0,108,
    100,97,0,108,100,120,0,108,100,121,0,115,116,97,0,115,
    116,120,0,112,104,97,0,112,108,97,0,116,120,97,0,116,
    97,120,0,116,97,121,0,116,121,97,0,99,108,99,0,115,
    101,99,0,97,100,99,0,115,98,99,0,97,110,100,0,111,
    114,97,0,97,115,108,0,114,111,108,0,108,115,114,0,114,
    111,114,0,105,110,121,0,100,101,121,0,98,101,113,0,98,
    110,101,0,106,109,112,0,106,115,114,0,114,116,115,0,101,
    111,114,0,32,35,60,0,32,35,62,0,32,40,78,67,95,
    80,84,82,41,44,121,0,32,61,32,36,0,32,61,32,78,
    67,95,66,83,83,43,36,0,43,49,0,95,95,76,0,95,
    95,99,95,105,111,95,99,108,111,115,101,95,95,118,48,0,
    95,95,99,95,105,111,95,99,114,101,97,116,101,95,95,118,
    48,0,95,95,99,95,105,111,95,111,112,101,110,95,95,118,
    48,0,95,95,99,95,105,111,95,114,101,97,100,95,95,118,
    48,0,95,95,99,95,105,111,95,119,114,105,116,101,95,95,
    118,48,0,95,95,102,0,95,95,103,0,95,95,118,0,98,
    121,116,101,32,36,0,9,112,104,97,10,9,116,120,97,10,
    9,112,104,97,10,0,9,112,108,97,10,9,116,97,120,10,
    9,112,108,97,10,0,9,112,108,97,10,9,115,116,97,32,
    78,67,95,84,77,80,43,49,10,9,112,108,97,10,9,115,
    116,97,32,78,67,95,84,77,80,10,9,112,108,97,10,9,
    116,97,120,10,9,112,108,97,10,0,9,99,108,99,10,9,
    97,100,99,32,78,67,95,84,77,80,10,9,116,97,121,10,
    9,116,120,97,10,9,97,100,99,32,78,67,95,84,77,80,
    43,49,10,9,116,97,120,10,9,116,121,97,10,0,9,115,
    101,99,10,9,115,98,99,32,78,67,95,84,77,80,10,9,
    116,97,121,10,9,116,120,97,10,9,115,98,99,32,78,67,
    95,84,77,80,43,49,10,9,116,97,120,10,9,116,121,97,
    10,0,9,97,110,100,32,78,67,95,84,77,80,10,9,116,
    97,121,10,9,116,120,97,10,9,97,110,100,32,78,67,95,
    84,77,80,43,49,10,9,116,97,120,10,9,116,121,97,10,
    0,9,111,114,97,32,78,67,95,84,77,80,10,9,116,97,
    121,10,9,116,120,97,10,9,111,114,97,32,78,67,95,84,
    77,80,43,49,10,9,116,97,120,10,9,116,121,97,10,0,
    9,112,108,97,10,9,116,97,120,10,9,112,108,97,10,9,
    101,111,114,32,35,36,102,102,10,9,99,108,99,10,9,97,
    100,99,32,35,36,48,49,10,9,116,97,121,10,9,116,120,
    97,10,9,101,111,114,32,35,36,102,102,10,9,97,100,99,
    32,35,36,48,48,10,9,116,97,120,10,9,116,121,97,10,
    9,112,104,97,10,9,116,120,97,10,9,112,104,97,10,0,
    31,4,36,3,40,8,49,2,52,4,57,5,63,5,69,6,
    0,0,61,61,142,33,61,143,60,61,144,62,61,145,60,60,
    146,62,62,147,0,0,0,9,108,100,121,32,78,67,95,84,
    77,80,10,0,9,97,115,108,10,9,115,116,97,32,78,67,
    95,84,77,80,43,49,10,9,116,120,97,10,9,114,111,108,
    10,9,116,97,120,10,9,108,100,97,32,78,67,95,84,77,
    80,43,49,10,0,9,115,116,97,32,78,67,95,84,77,80,
    43,49,10,9,116,120,97,10,9,108,115,114,10,9,116,97,
    120,10,9,108,100,97,32,78,67,95,84,77,80,43,49,10,
    9,114,111,114,10,0,9,100,101,121,10,0,9,108,100,121,
    32,35,36,48,48,10,9,108,100,97,32,40,78,67,95,80,
    84,82,41,44,121,10,9,108,100,120,32,35,36,48,48,10,
    9,112,104,97,10,9,116,120,97,10,9,112,104,97,10,0,
    9,108,100,121,32,35,36,48,48,10,9,108,100,97,32,40,
    78,67,95,80,84,82,41,44,121,10,9,115,116,97,32,78,
    67,95,84,77,80,10,9,105,110,121,10,9,108,100,97,32,
    40,78,67,95,80,84,82,41,44,121,10,9,116,97,120,10,
    9,108,100,97,32,78,67,95,84,77,80,10,9,112,104,97,
    10,9,116,120,97,10,9,112,104,97,10,0,9,112,108,97,
    10,9,115,116,97,32,78,67,95,84,77,80,43,49,10,9,
    112,108,97,10,9,115,116,97,32,78,67,95,84,77,80,10,
    9,112,108,97,10,9,115,116,97,32,78,67,95,80,84,82,
    43,49,10,9,112,108,97,10,9,115,116,97,32,78,67,95,
    80,84,82,10,9,108,100,121,32,35,36,48,48,10,9,108,
    100,97,32,78,67,95,84,77,80,10,9,115,116,97,32,40,
    78,67,95,80,84,82,41,44,121,10,0,9,112,108,97,10,
    9,115,116,97,32,78,67,95,84,77,80,43,49,10,9,112,
    108,97,10,9,115,116,97,32,78,67,95,84,77,80,10,9,
    112,108,97,10,9,115,116,97,32,78,67,95,80,84,82,43,
    49,10,9,112,108,97,10,9,115,116,97,32,78,67,95,80,
    84,82,10,9,108,100,121,32,35,36,48,48,10,9,108,100,
    97,32,78,67,95,84,77,80,10,9,115,116,97,32,40,78,
    67,95,80,84,82,41,44,121,10,9,105,110,121,10,9,108,
    100,97,32,78,67,95,84,77,80,43,49,10,9,115,116,97,
    32,40,78,67,95,80,84,82,41,44,121,10,0,9,97,115,
    108,10,9,115,116,97,32,78,67,95,84,77,80,10,9,116,
    120,97,10,9,114,111,108,10,9,116,97,120,10,9,108,100,
    97,32,78,67,95,84,77,80,10,0,9,99,108,99,10,9,
    97,100,99,32,35,60,0,10,9,115,116,97,32,78,67,95,
    80,84,82,10,9,116,120,97,10,9,97,100,99,32,35,62,
    0,10,9,115,116,97,32,78,67,95,80,84,82,43,49,10,
    0,9,99,108,99,10,9,97,100,99,32,0,10,9,115,116,
    97,32,78,67,95,80,84,82,10,9,116,120,97,10,9,97,
    100,99,32,0,43,49,10,9,115,116,97,32,78,67,95,80,
    84,82,43,49,10,0
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
char global_name[5120];
char global_name_len[160];
char global_kind[160];
char global_type[160];
unsigned global_array_len[160];
char global_param_start[160];
char global_param_count[160];
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
    int i;

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
    int high;
    int low;

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

    if (hold_valid != 0) {
        source_char = source_hold;
        hold_valid = 0;
        return 1;
    }
    value = io_read(source_handle);
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

char scan_token()
{
    int value;
    int digit;
    int base;
    int done;
    int comment_done;

    token_length = 0;
    token_value = 0;
    token_type = 0;

    done = 0;
    while (done == 0) {
        while (source_char == ' ' | source_char == 9 | source_char == 10) {
            if (step_source() == 0) {
                token_kind = 129;
                return 0;
            }
        }
        if (source_char == '/') {
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
        } else {
            done = 1;
        }
    }

    if (source_char < 0) {
        token_kind = 128;
        return 1;
    }

    if (is_letter(source_char) != 0) {
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

    if (is_digit(source_char) != 0) {
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
                        compiler_error = 2;
                        token_kind = 129;
                        return 0;
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

    if (source_char == 39) {
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

    if (source_char == 34) {
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

    value = source_char;
    if (step_source() == 0) {
        token_kind = 129;
        return 0;
    }
    digit = 1090;
    while (fixed_text[digit] != 0) {
        if (value == fixed_text[digit]) {
            if (source_char == fixed_text[digit + 1]) {
                token_kind = fixed_text[digit + 2];
                if (step_source() == 0) {
                    token_kind = 129;
                    return 0;
                }
                return 1;
            }
        }
        digit = digit + 3;
    }
    if (value == '!') {
        return scan_error();
    }
    token_kind = value;
    return 1;
}

char save_token_name()
{
    int i;

    if (token_length > 31) {
        compiler_error = 4;
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

char global_name_equal(char symbol)
{
    int i;
    int base;

    if (global_name_len[symbol] != token_length) {
        return 0;
    }
    base = symbol * 32;
    i = 0;
    while (i < token_length) {
        if (global_name[base + i] != token_text[i]) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

char current_name_equal(char symbol)
{
    int i;
    int base;

    if (local_name_len[symbol] != token_length) {
        return 0;
    }
    base = symbol * 32;
    i = 0;
    while (i < token_length) {
        if (local_name[base + i] != token_text[i]) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

int find_global()
{
    int i;

    i = 0;
    while (i < global_count) {
        if (global_name_equal(i) != 0) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

int find_current()
{
    int i;

    i = 0;
    while (i < local_count) {
        if (current_name_equal(i) != 0) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

int lookup_name()
{
    int id;

    id = find_current();
    if (id >= 0) {
        saved_area = 2;
        return id;
    }
    id = find_global();
    if (id >= 0) {
        saved_area = 1;
        return id;
    }
    return -1;
}

char copy_pending_global(char symbol)
{
    int i;
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
    int i;
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

    if (global_count >= 160) {
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
    int i;

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

    new_end = bss_offset + size;
    if (new_end > 34304) {
        compiler_error = 6;
        return 0;
    }
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

char emit_param_store(char function_id, char argument, char type)
{
    if (emit_zero((fixed_text + 455)) == 0) {
        return 0;
    }
    if (type != 1) {
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
        if (write_text((fixed_text + 584)) == 0) {
            return 0;
        }
        if (write_newline() == 0) {
            return 0;
        }
    }
    if (emit_zero((fixed_text + 455)) == 0) {
        return 0;
    }
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
    return write_newline();
}

char emit_push_ax()
{
    return write_text((fixed_text + 694));
}

char emit_pop_ax()
{
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
    return emit_push_ax();
}

char emit_array_address(char symbol)
{
    if (emit_instruction((fixed_text + 431)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 547)) == 0) {
        return 0;
    }
    if (emit_global_name(symbol) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    if (emit_instruction((fixed_text + 435)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 551)) == 0) {
        return 0;
    }
    if (emit_global_name(symbol) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    return emit_push_ax();
}

char emit_literal_value(unsigned value)
{
    if (emit_immediate((fixed_text + 431), value & 255) == 0) {
        return 0;
    }
    if (emit_immediate((fixed_text + 435), (value >> 8) & 255) == 0) {
        return 0;
    }
    return emit_push_ax();
}

char emit_string_literal()
{
    unsigned data_label;
    unsigned skip_label;
    int i;

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
    if (emit_instruction((fixed_text + 431)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 547)) == 0) {
        return 0;
    }
    if (emit_label_name(data_label) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    if (emit_instruction((fixed_text + 435)) == 0) {
        return 0;
    }
    if (write_text((fixed_text + 551)) == 0) {
        return 0;
    }
    if (emit_label_name(data_label) == 0) {
        return 0;
    }
    if (write_newline() == 0) {
        return 0;
    }
    return emit_push_ax();
}

char is_numeric_type(char type)
{
    if (type == 1) {
        return 1;
    }
    if (type == 2) {
        return 1;
    }
    if (type == 3) {
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
    if (is_numeric_type(actual) != 0) {
        if (is_numeric_type(expected) != 0) {
            return 1;
        }
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

char emit_compare(char op, char unsigned_compare)
{
    char *helper;

    helper = (fixed_text + 312);
    if (op == 142) {
        helper = (fixed_text + 312);
    } else {
        if (op == 143) {
            helper = (fixed_text + 322);
        } else {
            if (unsigned_compare != 0) {
                if (op == '<') {
                    helper = (fixed_text + 332);
                } else {
                    if (op == 144) {
                        helper = (fixed_text + 343);
                    } else {
                        if (op == '>') {
                            helper = (fixed_text + 354);
                        } else {
                            helper = (fixed_text + 365);
                        }
                    }
                }
            } else {
                if (op == '<') {
                    helper = (fixed_text + 376);
                } else {
                    if (op == 144) {
                        helper = (fixed_text + 387);
                    } else {
                        if (op == '>') {
                            helper = (fixed_text + 398);
                        } else {
                            helper = (fixed_text + 409);
                        }
                    }
                }
            }
        }
    }
    return emit_text_operand((fixed_text + 535), helper);
}

char reduce_unary()
{
    int type;

    if (value_top < 1) {
        compiler_error = 3;
        return 0;
    }
    type = value_type[value_top - 1];
    if (is_numeric_type(type) == 0) {
        compiler_error = 5;
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
    int left;
    int right;
    int result;
    int unsigned_compare;

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
    if (emit_push_ax() == 0) {
        return 0;
    }
    value_top = value_top - 1;
    value_type[value_top - 1] = result;
    return 1;
}

char reduce_top_operator()
{
    int op;

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
    int function_id;
    int argc;
    int base;
    int i;
    int expected;
    int actual;

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
    if (emit_push_ax() == 0) {
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
    int base;

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

char expression_value_step()
{
    int id;
    int area;
    int kind;
    int type;

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
        id = lookup_name();
        if (id < 0) {
            compiler_error = 4;
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

char expression_operator_step()
{
    int precedence;
    int top_precedence;
    int marker;
    int found;
    int id;
    int area;
    int kind;
    int type;

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
    if (token_kind == ']') {
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
        if (emit_index_load(area, id, kind, type) == 0) {
            return 0;
        }
        value_type[value_top - 1] = type;
        op_top = op_top - 1;
        if (scan_token() == 0) {
            return 0;
        }
        expr_expect = 0;
        return 1;
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
    if (element_type == 1) {
        return write_text((fixed_text + 1372));
    }
    return write_text((fixed_text + 1483));
}

int find_break_label()
{
    int i;

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

char parse_statements()
{
    int id;
    int area;
    int kind;
    int type;
    int frame;
    int break_label;
    unsigned first_label;
    unsigned second_label;

    ctrl_top = 0;
    while (1) {
        if (token_kind == '}') {
            if (ctrl_top == 0) {
                if (scan_token() == 0) {
                    return 0;
                }
                return 1;
            }
            frame = ctrl_top - 1;
            kind = ctrl_kind[frame];
            if (kind == 1) {
                ctrl_top = ctrl_top - 1;
                if (scan_token() == 0) {
                    return 0;
                }
            } else {
                if (kind == 4) {
                    if (emit_jump_label((fixed_text + 531), ctrl_label0[frame]) == 0) {
                        return 0;
                    }
                    if (emit_label(ctrl_label1[frame]) == 0) {
                        return 0;
                    }
                    ctrl_top = ctrl_top - 1;
                    if (scan_token() == 0) {
                        return 0;
                    }
                } else {
                    if (kind == 3) {
                        if (emit_label(ctrl_label1[frame]) == 0) {
                            return 0;
                        }
                        ctrl_top = ctrl_top - 1;
                        if (scan_token() == 0) {
                            return 0;
                        }
                    } else {
                        if (scan_token() == 0) {
                            return 0;
                        }
                        if (token_kind == 138) {
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
                            if (scan_token() == 0) {
                                return 0;
                            }
                        } else {
                            if (emit_label(ctrl_label0[frame]) == 0) {
                                return 0;
                            }
                            ctrl_top = ctrl_top - 1;
                        }
                    }
                }
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
                    first_label = label_counter;
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
                    if (emit_false_jump(first_label) == 0) {
                        return 0;
                    }
                    if (scan_token() == 0) {
                        return 0;
                    }
                    if (token_kind != '{') {
                        compiler_error = 3;
                        return 0;
                    }
                    if (push_control(2, first_label, 0) == 0) {
                        return 0;
                    }
                    if (scan_token() == 0) {
                        return 0;
                    }
                } else {
                    if (token_kind == 139) {
                        first_label = label_counter;
                        label_counter = label_counter + 1;
                        second_label = label_counter;
                        label_counter = label_counter + 1;
                        if (emit_label(first_label) == 0) {
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
                        if (emit_false_jump(second_label) == 0) {
                            return 0;
                        }
                        if (scan_token() == 0) {
                            return 0;
                        }
                        if (token_kind != '{') {
                            compiler_error = 3;
                            return 0;
                        }
                        if (push_control(4, first_label, second_label) == 0) {
                            return 0;
                        }
                        if (scan_token() == 0) {
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
                                id = lookup_name();
                                if (id < 0) {
                                    compiler_error = 4;
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
                                    if (scan_token() == 0) {
                                        return 0;
                                    }
                                } else {
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
                                        if (scan_token() == 0) {
                                            return 0;
                                        }
                                    } else {
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
                                            if (scan_token() == 0) {
                                                return 0;
                                            }
                                        } else {
                                            compiler_error = 3;
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
    }
}

char parse_type()
{
    int type;

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
    int negative;

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
    int width;

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
    int type;
    int slot;

    type = parse_type();
    if (type == 0) {
        return 0;
    }
    if (token_kind != 130) {
        compiler_error = 3;
        return 0;
    }
    if (find_current() >= 0) {
        compiler_error = 4;
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
    int type;
    int slot;
    int param_start;

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
            if (find_current() >= 0) {
                compiler_error = 4;
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
    int type;
    int symbol;
    int functions_started;

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
        if (find_global() >= 0) {
            compiler_error = 4;
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
        return 1;
    }
    output_handle = io_create(output_name, output_length);
    if (output_handle < 0) {
        io_close(source_handle);
        return 1;
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
    if (emit_include((fixed_text + 153)) == 0) {
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

int main()
{
    return compile_file((fixed_text + 0), 20, (fixed_text + 21), 9);
}
