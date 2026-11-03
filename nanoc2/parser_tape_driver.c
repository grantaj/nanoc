/*
 * Host-only authority test: the ORIGINAL nanoc1 semantic parser produces
 * function-local nodes and statement events. It does not use source_tape.c.
 * The original emitter's text is discarded during this transition.
 */
#include <stdio.h>
#include <stdlib.h>
#define main original_nanoc1_main
#include "parser_tape.c"
#undef main

static char source_buffer[110000];
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

int main(void)
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
    if (init_symbols() == 0) return 3;
    if (next_source_char() == 0 || scan_token() == 0) return 4;
    if (parse_unit() == 0 || nc2_fault != 0) {
        fprintf(stderr,"parser error %d, tape error %d, token %d, node %u, event %u\n",
                compiler_error,nc2_fault,token_kind,nc2_nodes,nc2_events);
        return 5;
    }
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
