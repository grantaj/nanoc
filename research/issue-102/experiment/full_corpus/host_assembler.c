/* Research validation: use exact candidate Phase-1 assembler C source as
 * the assembler, NOT a reimplementation. Only 6502 instruction syntax is
 * being verified; the backend's runtime ABI remains hypothetical. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static FILE *handles[6];
int io_open(char *name, int length) {
 char temp[300];
 if(length<0 || length>290)return -2;
 memcpy(temp,name,(size_t)length);temp[length]=0;
 for(int i=1;i<=5;i++)if(!handles[i]){handles[i]=fopen(temp,"rb");return handles[i]?i:-2;}
 return -2;
}
int io_read(int handle) {if(handle<1||handle>5||!handles[handle])return -2;int c=fgetc(handles[handle]);return c==EOF?-1:c;}
char io_close(int handle) {if(handle<1||handle>5||!handles[handle])return 1;fclose(handles[handle]);handles[handle]=NULL;return 0;}
#include "ass.c"
int main(int argc,char**argv) {
 if(argc<2)return 2;
 int st=ass_assemble(argv[1],(char)strlen(argv[1]),"",0,0x0800);
 if(st!=ASSEMBLE_OK){fprintf(stderr,"ASSEMBLER STATUS: %d line length %d source depth %d\n",st,source_line_length,source_depth);
 fprintf(stderr,"Failed statement: %.*s\n",(int)source_line_length,source_line);return st?st:1;}
 printf("assembled %d bytes\n",ass_image_length);
 return 0;
}
