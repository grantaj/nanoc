/* Host-only adapter to check the C emitter, not part of Phase-1. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "traversal_backend.c"

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

void enter(char op,char d,char a,char b,unsigned k)
{
    if (!tb_add(op,d,a,b,k)) { fprintf(stderr,"tape overflow\n"); exit(1); }
}

void same_bytes(void)
{
    /* Semantics of nanoc1.c::same_bytes; both pointer args in ZP. */
    tb_reset();
    enter(9,3,4,0,0);        /* if a_length != b_length return 0 */
    enter(10,0,2,0,99);
    enter(2,1,0,0,0);        /* i = 0 */
    enter(1,0,0,0,10);
    enter(9,1,3,0,0);        /* if i >= a_length return 1 */
    enter(10,0,4,0,98);
    enter(6,0,0,1,0);        /* A = a[i] */
    enter(7,0,1,1,0);        /* compare b[i] */
    enter(10,0,2,0,99);
    enter(3,1,0,0,0);        /* i++ */
    enter(11,0,0,0,10);
    enter(1,0,0,0,98);
    enter(13,0,0,0,1);
    enter(1,0,0,0,99);
    enter(13,0,0,0,0);
    if (!tb_compile()) { fprintf(stderr,"compile error %u\n",tb_error); exit(1); }
}

void find_global(void)
{
    /* Semantics of nanoc1.c::find_global with byte symbol/index and
     * 32-byte fixed records, retaining the nested early-break structure.
     * The global text/length arrays are not read by a named routine recipe.
     */
    tb_reset();
    enter(2,1,0,0,0);       /* symbol = 0 */
    enter(1,0,0,0,10);      /* outer loop */
    enter(9,1,5,0,0);       /* symbol >= global_count ? */
    enter(10,0,4,0,99);
    enter(4,0,1,1,0);       /* A = global_name_len[symbol] */
    enter(18,0,4,0,0);      /* compare A to token_length */
    enter(10,0,2,0,40);
    enter(14,0,2,1,32);     /* ptr0 = global_name + 32 * symbol */
    enter(2,2,0,0,0);       /* i=0, Y index */
    enter(2,3,0,0,1);       /* match=1 */
    enter(1,0,0,0,20);      /* inner loop */
    enter(9,2,4,0,0);       /* i>=token_length? */
    enter(10,0,4,0,30);
    enter(6,0,0,2,0);       /* A = ptr0[i] */
    enter(5,0,3,2,0);       /* compare token_text[i] */
    enter(10,0,2,0,25);    /* break if mismatch */
    enter(3,2,0,0,0);       /* i++ */
    enter(11,0,0,0,20);
    enter(1,0,0,0,25);      /* mismatch: */
    enter(2,3,0,0,0);       /* match=0 */
    enter(1,0,0,0,30);      /* after inner loop */
    enter(8,3,0,0,1);       /* if match==1 return symbol */
    enter(10,0,2,0,40);
    enter(12,1,0,0,0);
    enter(1,0,0,0,40);      /* next symbol */
    enter(3,1,0,0,0);
    enter(11,0,0,0,10);
    enter(1,0,0,0,99);
    enter(13,0,0,0,255);
    if (!tb_compile()) { fprintf(stderr,"compile error %u\n",tb_error); exit(1); }
}

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    if (!strcmp(argv[1],"same_bytes")) same_bytes();
    else if (!strcmp(argv[1],"find_global")) find_global();
    else return 2;
    return 0;
}
