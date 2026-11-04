/*
 * Native Nano C ABI boundary for the traversal-first emitter.
 *
 * This is not a second parser or code generator. It gives the same operation
 * tape ordinary Nano C static parameter/local/global homes and initializes
 * the zero-page traversal pointers when a function is entered.
 *
 * Each byte-returning function is emitted when its existing Phase-1 parser
 * finishes it. Uninitialized globals share the translation-unit BSS map;
 * byte calls use the original static argument slots. The general Phase-1
 * ABI (wide values, pointer-live calls and runtime services) follows.
 */
char n2_name(char area, char slot)
{
    if (area==1) {
        if (tb_text("__g")==0) return 0;
    } else {
        if (tb_text("__v")==0) return 0;
    }
    if (area == 2) {
        if (tb_hex2(nc2_function_symbol) == 0) return 0;
        if (tb_char('_') == 0) return 0;
    }
    return tb_hex2(slot);
}

char n2_function_name()
{
    if (tb_text("__c") == 0) return 0;
    return tb_hex2(nc2_function_symbol);
}

char n2_home(char area, char slot, unsigned offset)
{
    if (n2_name(area,slot) == 0) return 0;
    if (tb_text(" = NC_BSS+$") == 0) return 0;
    if (tb_hex4(offset) == 0) return 0;
    return tb_char('\n');
}

char n2_alias(char area, char slot, char *names, char length)
{
    unsigned i;
    if (tb_text("n2_") == 0) return 0;
    i=0;
    while (i<length) {
        if (tb_char(names[i]) == 0) return 0;
        i=i+1;
    }
    if (tb_text(" = ") == 0) return 0;
    if (n2_name(area,slot) == 0) return 0;
    return tb_char('\n');
}

/* Locals have existing Nano C global-static ABI homes, but their slot
 * numbers restart at zero for every function. Emit equates while this
 * function's symbol/type table is still live, immediately after its body.
 */

char n2_function_alias()
{
    char i;
    if (tb_text("n2_")==0) return 0;
    i=0;
    while(i<global_name_len[nc2_function_symbol]) {
        if (tb_char(global_name[(unsigned)nc2_function_symbol*32+i])==0)
            return 0;
        i=i+1;
    }
    if (tb_text(" = ")==0) return 0;
    if (n2_function_name()==0) return 0;
    return tb_char('\n');
}

/* Local names repeat between functions. The assembler aliases used by
 * native tests and diagnostics therefore include the owning function.
 * The first function also retains legacy unqualified aliases for the
 * original four-function native smoke tests.
 */
char n2_scoped_alias(char slot)
{
    char i;
    if (tb_text("n2_")==0) return 0;
    i=0;
    while(i<global_name_len[nc2_function_symbol]) {
        if(tb_char(global_name[(unsigned)nc2_function_symbol*32+i])==0)
            return 0;
        i=i+1;
    }
    if(tb_char('_')==0) return 0;
    i=0;
    while(i<local_name_len[slot]) {
        if(tb_char(local_name[(unsigned)slot*32+i])==0) return 0;
        i=i+1;
    }
    if(tb_text(" = ")==0) return 0;
    if(n2_name(2,slot)==0) return 0;
    return tb_char('\n');
}

/* The parser flushes the bounded tape at each function's closing brace.
 * Only the symbol homes survive, as ordinary assembly equates. */
unsigned n2_global_limit;
char n2_first_function;
char n2_started;

char n2_local_bss()
{
    char slot;
    unsigned offset;
    offset=nc2_local_base;
    slot=0;
    while(slot<nc2_local_slots) {
        if(n2_home(2,slot,offset)==0) return 0;
        if(n2_scoped_alias(slot)==0) return 0;
        /* Unqualified source-name aliases exist solely for the single-
         * function native test caller. A second function may reuse a local
         * name and must not create a duplicate assembler equate. */
        if(nc2_function_count==1) {
            if(n2_alias(2,slot,local_name+((unsigned)slot*32),
                        local_name_len[slot])==0) return 0;
        }
        offset=offset+type_size(local_type[slot]);
        slot=slot+1;
    }
    if(offset!=bss_offset) { tb_error=35; return 0; }
    return 1;
}

char n2_global_bss()
{
    char slot;
    unsigned offset;
    unsigned size;
    slot=0;
    offset=0;
    while(slot<global_count) {
        if(global_kind[slot]==1 | global_kind[slot]==2) {
            if(global_kind[slot]==1) size=type_size(global_type[slot]);
            else size=global_array_len[slot]*type_size(global_type[slot]);
            /* Initialized globals already have physically emitted
             * __gXX labels in the code/data image. They must not also
             * consume BSS offsets or be emitted as conflicting equates. */
            if(nc2_initialized_global[slot]==0) {
                if(n2_home(1,slot,offset)==0) return 0;
                offset=offset+size;
            }
            if(n2_alias(1,slot,global_name+((unsigned)slot*32),
                        global_name_len[slot])==0) return 0;
        }
        slot=slot+1;
    }
    if(offset!=n2_global_limit) { tb_error=36; return 0; }
    return 1;
}

char n2_pointer_prologue()
{
    char slot;
    int entry;
    slot=0;
    while (slot<nd_next_pointer) {
        entry=nd_find(nd_ptr_area[slot],nd_ptr_symbol[slot]);
        if (entry<0) {tb_error=33;return 0;}
        if (nd_map_kind[entry]==3) {
            if (tb_text("\tlda ")==0) return 0;
            if (n2_name(nd_ptr_area[slot],nd_ptr_symbol[slot])==0) return 0;
            if (tb_char('\n')==0) return 0;
            if (tb_text("\tsta __tptr")==0) return 0;
            if (tb_hex2(slot)==0) return 0;
            if (tb_char('\n')==0) return 0;
            if (tb_text("\tlda ")==0) return 0;
            if (n2_name(nd_ptr_area[slot],nd_ptr_symbol[slot])==0) return 0;
            if (tb_text("+1\n\tsta __tptr")==0) return 0;
            if (tb_hex2(slot)==0) return 0;
            if (tb_text("+1\n")==0) return 0;
        }
        slot=slot+1;
    }
    return 1;
}

/* Single translation unit: one entry point, one function at a time.
 * The executable begins with a jump to the selected entry; names are
 * resolved after all function definitions have been processed. */
char n2_begin()
{
    n2_started=0;
    n2_first_function=255;
    nc2_builtin_used=0;
    if(tb_text("NC_BSS = $4800\n")==0) return 0;
    /* C64 KERNAL interrupts use $f0-$fa. Only $fb-$fe are available
     * for user-owned indirect-index cursors, and the existing Nano C
     * runtime uses these four bytes as NC_TMP/NC_PTR. Calls with live
     * pointer cursors are rejected until we add save/restore semantics.
     * Other scratch needs ordinary private RAM; never borrow IRQ ZP.
     */
    if(tb_text("__tptr00 = $fb\n__tptr01 = $fd\n")==0) return 0;
    if(tb_text("__twlo = $cf20\n__twhi = $cf21\n__tret = $cf22\n__trethi = $cf23\n__tacc = $cf24\n__tidxsave = $cf26\n__targ = $cf27\n__tbyte = $cf29\n")==0) return 0;
    if(tb_text("\t* = $0800\n__nc_start:\n\tjmp __nc_entry\n")==0) return 0;
    return 1;
}

char n2_emit_function()
{
    if(n2_first_function==255) {
        n2_first_function=nc2_function_symbol;
        n2_global_limit=nc2_local_base;
    }
    if(nd_prepare()==0) return 0;
    if(n2_function_name()==0) return 0;
    if(tb_text(":\n")==0) return 0;
    if(n2_pointer_prologue()==0) return 0;
    /* An incoming byte parameter may be assigned to X/Y by the
     * direct-index traversal plan. Unlike a local loop induction
     * variable it has not yet been initialized by a function event.
     * Seed both selected registers from their static Nano C homes
     * at the ABI boundary; subsequent tape writes update them. */
    if(tb_plan()==0) return 0;
    if(tb_x!=0) {
        if(tb_location("ldx",1,tb_x,"")==0) return 0;
    }
    if(tb_y!=0) {
        if(tb_location("ldy",1,tb_y,"")==0) return 0;
    }
    if(tb_compile()==0) return 0;
    if(n2_function_alias()==0) return 0;
    if(n2_local_bss()==0) return 0;
    n2_started=1;
    return 1;
}

char n2_end()
{
    char entry;
    if(n2_started==0) { tb_error=34; return 0; }
    if(main_symbol>=0) {
        if(global_param_count[main_symbol]!=0) { tb_error=37; return 0; }
        entry=main_symbol;
    } else entry=n2_first_function;
    if(nc2_builtin_used!=0) {
        /* Builtins are normal typed call events, with original static
         * two-byte parameter homes. Only their final linker names differ.
         * Keep these aliases out of no-I/O units entirely. */
        if(tb_text("__c00 = __c_io_open\n__c01 = __c_io_read\n")==0)
            return 0;
        if(tb_text("__c02 = __c_io_create\n__c03 = __c_io_write\n")==0)
            return 0;
        if(tb_text("__c04 = __c_io_close\n")==0) return 0;
        if(tb_text("__v00_00 = __c_io_open__v00\n")==0) return 0;
        if(tb_text("__v00_01 = __c_io_open__v01\n")==0) return 0;
        if(tb_text("__v01_00 = __c_io_read__v00\n")==0) return 0;
        if(tb_text("__v02_00 = __c_io_create__v00\n")==0) return 0;
        if(tb_text("__v02_01 = __c_io_create__v01\n")==0) return 0;
        if(tb_text("__v03_00 = __c_io_write__v00\n")==0) return 0;
        if(tb_text("__v03_01 = __c_io_write__v01\n")==0) return 0;
        if(tb_text("__v04_00 = __c_io_close__v00\n")==0) return 0;
        /* Startup initializes six I/O handle slots before entering
         * user C. Individual native test callers can initialize them
         * explicitly through the exported n2_io_init alias. */
        if(tb_text("n2_io_init = __nc_io_init\n")==0) return 0;
        if(tb_text("__nc_entry:\n\tjsr __nc_io_init\n\tjmp __c")==0)
            return 0;
        if(tb_hex2(entry)==0) return 0;
        if(tb_char('\n')==0) return 0;
    } else {
        if(tb_text("__nc_entry = __c")==0) return 0;
        if(tb_hex2(entry)==0) return 0;
        if(tb_char('\n')==0) return 0;
    }
    if(n2_global_bss()==0) return 0;
    if(nc2_builtin_used!=0)
        return tb_text("\tinclude \"nanoc2/target/io-runtime.asm\"\n");
    return 1;
}
