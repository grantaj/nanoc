/* Host-only I/O/ABI adapter. The compiler proper uses Nano C's scanner and
 * symbol information; the names below just bind the two test ABI layouts. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "traversal_backend.c"
#include "source_tape.c"

char tb_char(char c) { return putchar(c) == EOF ? 0 : 1; }
char *tb_name(char category, char number)
{
    static char name[20];
    if (category == 1) {
        snprintf(name,sizeof(name),"__v%u",(unsigned char)number);
        return name;
    }
    if (category == 2) {
        if (number == 1) return "global_name_len";
        if (number == 2) return "global_name";
        if (number == 3) return "token_text";
    }
    return "BAD_SYMBOL";
}

int main(int argc, char **argv)
{
    static char input[12000];
    size_t count;
    if (argc != 2) return 2;
    count = fread(input,1,sizeof(input)-1,stdin);
    if (count >= sizeof(input)-1) return 3;
    input[count] = 0;
    ta_bindings = 0;
    if (!strcmp(argv[1],"same_bytes")) {
        ta_register("i",1,1);
        ta_register("a",3,0); ta_register("b",3,1);
        ta_register("a_length",1,3); ta_register("b_length",1,4);
    } else if (!strcmp(argv[1],"find_global")) {
        ta_register("symbol",1,1); ta_register("i",1,2);
        ta_register("match",1,3); ta_register("base",4,0);
        ta_register("token_length",1,4); ta_register("global_count",1,5);
        ta_register("global_name_len",2,1);
        ta_register("global_name",2,2); ta_register("token_text",2,3);
    } else return 2;
    if (!ta_compile_source(input)) {
        fprintf(stderr,"source-to-tape rejected input (error %u, token '%s')\n",
                (unsigned char)ta_error, ta_token);
        return 1;
    }
    return 0;
}
