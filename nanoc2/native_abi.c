/*
 * Native Nano C ABI boundary for the traversal-first emitter.
 *
 * This is not a second parser or code generator. It gives the same operation
 * tape ordinary Nano C static parameter/local/global homes and initializes
 * the zero-page traversal pointers when a function is entered.
 *
 * The first native slice accepts one byte-returning Phase-1 function and
 * uninitialized globals. The complete translation-unit/call ABI follows.
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
unsigned n2_global_end;
unsigned n2_last_local_end;

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

char n2_local_homes()
{
    unsigned offset;
    char i;
    offset=nc2_local_base;
    i=0;
    while(i<nc2_local_slots) {
        if (n2_home(2,i,offset)==0) return 0;
        if (n2_alias(2,i,local_name+((unsigned)i*32),
                     local_name_len[i])==0) return 0;
        offset=offset+type_size(local_type[i]);
        i=i+1;
    }
    n2_last_local_end=offset;
    return 1;
}

char n2_bss()
{
    char i;
    unsigned offset;
    unsigned size;
    offset=0;
    i=0;
    while (i<global_count) {
        if (global_kind[i]==1 | global_kind[i]==2) {
            if (global_kind[i]==1) size=type_size(global_type[i]);
            else {
                if (global_type[i]!=1) {tb_error=31;return 0;}
                size=global_array_len[i];
            }
            if (n2_home(1,i,offset)==0) return 0;
            if (n2_alias(1,i,global_name+((unsigned)i*32),
                         global_name_len[i])==0) return 0;
            offset=offset+size;
        }
        i=i+1;
    }
    /* No initialized global data in this slice. The exact byte extent
     * is independently tracked by the production parser's BSS allocator.
     * All per-function statics must be accounted for exactly once. */
    if(offset!=n2_global_end | n2_last_local_end!=bss_offset |
       bss_offset>34304) {tb_error=32;return 0;}
    return 1;
}

/* Reconstruct the two live Y-indexed pointers from real Nano C static
 * pointer parameters, not from a test harness's preloaded ZP values.
 * A scaled array pointer has a different producer inside the function
 * and is intentionally NOT reloaded at entry.
 */
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

/* Called when the ORIGINAL parser finishes a function, before it erases
 * its bounded node/event tape and local symbol table. The backend retains
 * only one function in memory at a time, even for a large translation unit.
 */
char n2_emit_function()
{
    if (nd_prepare()==0) return 0;
    if (nc2_function_count==1) {
        n2_global_end=nc2_local_base;
        if (tb_text("NC_BSS = $4800\n")==0) return 0;
        if (tb_text("__tptr00 = $f0\n__tptr01 = $f2\n")==0) return 0;
        if (tb_text("__twlo = $f4\n__twhi = $f5\n")==0) return 0;
        if (tb_text("\t* = $0800\n__nc_start:\n\tjmp ")==0) return 0;
        if (n2_function_name()==0) return 0;
        if (tb_char('\n')==0) return 0;
    }
    if (n2_function_name()==0) return 0;
    if (tb_text(":\n")==0) return 0;
    if (n2_pointer_prologue()==0) return 0;
    if (tb_compile()==0) return 0;
    if (n2_function_alias()==0) return 0;
    return n2_local_homes();
}

/* Called only after the complete source unit has been parsed. Globals
 * may be forward-referenced and the callee's static argument homes are
 * defined by the same equate pass. */
char n2_native()
{
    if (nc2_function_count==0) {tb_error=34;return 0;}
    return n2_bss();
}
