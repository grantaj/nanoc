/*
 * Host-only authority test: the ORIGINAL nanoc1 semantic parser produces
 * function-local nodes and statement events. It does not use source_tape.c.
 * The original emitter's text is discarded during this transition.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* Host-side Nano C I/O adapter; declarations precede the original parser
 * so strict host compilers can type-check it without implicit prototypes. */
int io_read(int h);
int io_write(int h, int c);
int io_open(char *path, int length);
int io_create(char *path, int length);
int io_close(int h);
#define main original_nanoc1_main
#include "parser_tape.c"
#undef main
#include "traversal_backend.c"
#include "lower_tape.c"
#include "native_abi.c"

static char source_buffer[110000];
static int native_mode;
static unsigned source_position;
int io_read(int h)
{
    int c;
    (void)h;
    c = (unsigned char)source_buffer[source_position];
    if (c == 0) return -1;
    source_position = source_position + 1;
    return c;
}
int io_write(int h, int c) { (void)h; (void)c; return 0; }
int io_open(char *path,int length) { (void)path; (void)length; return -2; }
int io_create(char *path,int length) { (void)path; (void)length; return -2; }
int io_close(int h) { (void)h; return 0; }

char tb_char(char c)
{
    return putchar(c)==EOF ? 0 : 1;
}
char *tb_name(char category, char number)
{
    static char tmp[24];
    if (native_mode) {
        if (category==1) {
            if (number==0 | number>=nd_next_scalar) return "INVALID_HOME";
            if (nd_var_area[number]==1)
                snprintf(tmp,sizeof(tmp),"__g%02X",
                         (unsigned char)nd_var_symbol[number]);
            else
                snprintf(tmp,sizeof(tmp),"__v%02X_%02X",
                         (unsigned char)nc2_function_symbol,
                         (unsigned char)nd_var_symbol[number]);
            return tmp;
        }
        if (category==2) {
            if (number==0 | number>=nd_next_array) return "INVALID_ARRAY";
            snprintf(tmp,sizeof(tmp),"__g%02X",
                     (unsigned char)nd_array_symbol[number]);
            return tmp;
        }
        return "INVALID_HOME";
    }
    if (category==1) {
        snprintf(tmp,sizeof(tmp),"__v%u",(unsigned char)number);
        return tmp;
    }
    if (category==2) {
        if (number==0 | number>=nd_next_array) return "INVALID_ARRAY";
        return global_name+(unsigned)nd_array_symbol[number]*32;
    }
    return "INVALID_HOME";
}
int main(int argc,char **argv)
{
    size_t n;
    unsigned i;
    n = fread(source_buffer,1,sizeof(source_buffer)-1,stdin);
    if (n >= sizeof(source_buffer)-1) return 2;
    source_buffer[n] = 0;
    source_position = 0;
    source_handle = 1;
    output_handle = 1;
    source_char = -1;
    hold_valid = 0;
    source_line = 1;
    compiler_error = 0;
    label_counter = 0;
    bss_offset = 0;
    param_count = 0;
    global_count = 0;
    main_symbol = -1;
    nc2_enable = 1;
    nc2_function_count = 0;
    nc2_local_slots = 0;
    if (init_symbols() == 0) return 3;
    if (next_source_char() == 0 || scan_token() == 0) return 4;
    if (parse_unit() == 0 || nc2_fault != 0) {
        fprintf(stderr,"parser error %d, tape error %d, token %d, node %u, event %u\n",
                compiler_error,nc2_fault,token_kind,nc2_nodes,nc2_events);
        return 5;
    }
    if (argc==2 && strcmp(argv[1],"native")==0) {
        native_mode=1;
        if(n2_native()==0) {
            fprintf(stderr,"native ABI error %u, lowerer %u, backend %u\n",
                    (unsigned)nc2_fault,(unsigned)nd_error,(unsigned)tb_error);
            return 7;
        }
        return 0;
    }
    if (argc==2 && strcmp(argv[1],"dump")==0) {
    printf("NODES %u EVENTS %u\n",nc2_nodes,nc2_events);
    for (i=1; i<nc2_nodes; i++)
        printf("N %u %u %u %u %u %u %u\n",i,nc2_kind[i],nc2_a[i],
               nc2_b[i],nc2_left[i],nc2_right[i],nc2_number[i]);
    for (i=0; i<nc2_events; i++)
        printf("E %u %u %u %u %u %u\n",i,nc2_event_kind[i],
               nc2_event_area[i],nc2_event_symbol[i],
               nc2_event_node[i],nc2_event_label[i]);
        return 0;
    }
    if (argc!=1) return 2;
    if (nd_compile()==0) {
        fprintf(stderr,"lowerer error %u, tb error %u; events %u\n",
                (unsigned)nd_error,(unsigned)tb_error,nc2_events);
        return 6;
    }
    for (i=1;i<nd_next_scalar;i++) {
        fprintf(stderr,"NC2VAR %s %u\n",
                nd_source_name(nd_var_area[i],nd_var_symbol[i]),i);
    }
    for (i=0;i<nd_next_pointer;i++) {
        fprintf(stderr,"NC2PTR %s %u\n",
                nd_source_name(nd_ptr_area[i],nd_ptr_symbol[i]),i);
    }
    return 0;
}
