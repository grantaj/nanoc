/* Host-only byte-stream adapter: exercises the ORIGINAL Nano C semantic parser
 * now sending events to the replacement C 6502 emitter. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define main nanoc1_original_main
#include "integrated.c"
#undef main
static unsigned char input[65536];
static size_t input_len,input_at;
int io_open(char *name,int size) {(void)name;(void)size;return 1;}
int io_create(char *name,int size) {(void)name;(void)size;return 2;}
int io_read(int handle) {(void)handle; if(input_at>=input_len) return -1;return input[input_at++];}
int io_write(int handle,int c) {(void)handle;return putchar((unsigned char)c)==EOF?-1:0;}
int io_close(int handle) {(void)handle;return 0;}
int main(void) {
    int err;
    input_len=fread(input,1,sizeof(input),stdin);
    if(input_len==sizeof(input)) {fprintf(stderr,"Input too big\n");return 99;}
    err=compile_file("INPUT.C",7,"OUT.ASM",7);
    if(err) fprintf(stderr,"nanoc2: compiler status %d, line %u\n",err,(unsigned)source_line);
    return err;
}
