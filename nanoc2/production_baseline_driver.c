/*
 * Host I/O bridge for the UNMODIFIED production nanoc1 compiler.
 * The same exact C function source is fed to it and nanoc2.
 * This file only replaces C64 file handles with host stdin/stdout.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int io_read(int handle);
int io_write(int handle,int value);
int io_open(char *name,int length);
int io_create(char *name,int length);
int io_close(int handle);

#define main nanoc1_original_main
#include "../nanoc1/nanoc1.c"
#undef main

static unsigned char host_source[32768];
static unsigned host_length;
static unsigned host_position;

int io_open(char *name,int length)
{
    (void)name; (void)length;
    host_position=0;
    return 1;
}
int io_read(int handle)
{
    (void)handle;
    if (host_position>=host_length) return -1;
    return host_source[host_position++];
}
int io_create(char *name,int length)
{
    (void)name; (void)length;
    return 2;
}
int io_write(int handle,int value)
{
    (void)handle;
    return putchar((unsigned char)value)==EOF ? -1 : 0;
}
int io_close(int handle) { (void)handle; return 0; }

int main(void)
{
    char source_path[]="BENCH.C";
    char out_path[]="BENCH.ASM";
    int result;
    size_t count;
    count=fread(host_source,1,sizeof(host_source),stdin);
    if(count==sizeof(host_source)) return 2;
    host_length=(unsigned)count;
    result=compile_file(source_path,7,out_path,9);
    if(result!=0) {
        fprintf(stderr,"nanoc1 compiler error %d at line %u\n",
                result,source_line);
        return result;
    }
    return fflush(stdout)==0 ? 0 : 3;
}
