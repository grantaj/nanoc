char ASSEMBLE_OK;
char ASSEMBLE_BAD_STATEMENT;
char ASSEMBLE_BAD_SYMBOL;
char ASSEMBLE_SYMBOL_FULL;
char ASSEMBLE_SCOPE_ERROR;
char ASSEMBLE_BAD_INSTRUCTION;
char ASSEMBLE_UNDEFINED;
char ASSEMBLE_EMIT_ERROR;
char ASSEMBLE_BAD_DATA;
char ASSEMBLE_BAD_ORIGIN;
char ASSEMBLE_WORK_FULL;
char ASSEMBLE_IO_ERROR;
char ASSEMBLE_LINE_TOO_LONG;
char ASSEMBLE_INCLUDE_DEPTH;
char MODE_IMPLIED;
char MODE_ACCUMULATOR;
char MODE_IMMEDIATE;
char MODE_ZERO_PAGE;
char MODE_ZERO_PAGE_X;
char MODE_ZERO_PAGE_Y;
char MODE_ABSOLUTE;
char MODE_ABSOLUTE_X;
char MODE_ABSOLUTE_Y;
char MODE_INDIRECT;
char MODE_INDIRECT_X;
char MODE_INDIRECT_Y;
char MODE_RELATIVE;
char mode_width[14];
char mnemonic_table[172];
char opcode_mnemonic[256];
char opcode_mode[256];
char ass_image[11264];
int ass_image_length;
unsigned ass_origin;
char source_line[256];
char source_line_length;
char source_path[256];
char source_handle[5];
int source_depth;
char *source_directory;
char source_directory_length;
int symbol_name_offset[896];
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
int fixup_count;
char SYMBOL_CONSTANT;
char SYMBOL_LABEL_UNDEFINED;
char SYMBOL_LABEL_DEFINED;
char VALUE_OK;
char VALUE_UNRESOLVED;
char VALUE_BAD;
char VALUE_SYMBOL_FULL;
char VALUE_SCOPE_ERROR;
char VALUE_PREFIX_NONE;
char VALUE_PREFIX_LOW;
char VALUE_PREFIX_HIGH;
unsigned value_result;
int captured_symbol;
unsigned captured_addend;
char captured_prefix;
unsigned atom_value;
int atom_symbol;
char atom_used;
char atom_kind;
char FIXUP_NONE;
char FIXUP_BYTE;
char FIXUP_WORD;
char FIXUP_RELATIVE;
char FIXUP_DATA_BYTE;
char origin_allowed;
char upper_char(char c);
char same_text(char *a, char a_length, char *b, char b_length);
char apply_byte_prefix(unsigned value, char prefix);
int hex_nibble(char c);
char append_fixup(char kind, int stage, int symbol, unsigned addend, char prefix);
int relative_byte(unsigned target, unsigned base);
char trim_fixups();
char resolve_fixups_for_symbol(int symbol);
int scope_for_name(char *name, char length);
int find_symbol(char *name, char length);
int allocate_symbol(char *name, char length, char kind, unsigned payload);
int intern_label(char *name, char length);
char define_constant(char *name, char length, unsigned value);
char patch_word_chain(int head, unsigned value);
char define_label(char *name, char length, unsigned value);
char parse_atom(char *text, char length);
char parse_value(char *text, char length);
int find_mnemonic(char *name, char length);
int find_opcode(char mnemonic, char mode);
char stage_byte(char value);
char stage_plain_word_reference(int symbol);
char stage_resolved_instruction(char opcode, char mode, unsigned value);
char stage_resolved_relative(char opcode, unsigned target);
char stage_unresolved_instruction(char opcode, char mode, int symbol, unsigned addend, char prefix);
char short_mode_for_index(char index);
char long_mode_for_index(char index);
char assemble_mode_value(char mnemonic, char mode, char *text, char length);
char assemble_direct_value(char mnemonic, char *text, char length, char index);
char assemble_instruction(char *name, char name_length, char *argument, char argument_length);
char stage_data_value(char *text, char length, char width);
char assemble_data_list(char *argument, char length, char width);
char assemble_string(char *argument, char length);
char open_include(char *argument, char length);
int read_source_line();
char close_source_tree();
int scan_argument(char start);
char process_label(char *name, char length);
char process_symbol(char *name, char name_length, char *argument, char argument_length);
char process_instruction_like(char *name, char name_length, char *argument, char argument_length);
char process_source_line();
char reset_assembler(unsigned default_origin, char *directory, char directory_length);
char all_symbols_defined();
char all_fixups_resolved();
char ass_assemble(char *root_name, char root_name_length, char *directory, char directory_length, unsigned default_origin);
int io_open(char *name, int length);
int io_read(int handle);
char io_close(int handle);
char stage_resolved_instruction(char opcode, char mode, unsigned value)
{
  char width;
  char status;
  width = mode_width[mode];
  if (width == 1)
  {
    if (value > 255)
    {
      return ASSEMBLE_BAD_INSTRUCTION;
    }
  }
  status = stage_byte(opcode);
  if (status != ASSEMBLE_OK)
  {
    return status;
  }
  if (width == 0)
  {
    return ASSEMBLE_OK;
  }
  status = stage_byte(value & 255);
  if (status != ASSEMBLE_OK)
  {
    return status;
  }
  if (width == 2)
  {
    return stage_byte((value >> 8) & 255);
  }
  return ASSEMBLE_OK;
}


