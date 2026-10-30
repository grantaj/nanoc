/* Host-only I/O for comparing two actual Phase-1 C assembler sources.
 * Build with -DNATIVE_ALGORITHM=1 for bootstrap/ass_native.c. */
#include <stdio.h>
#include <string.h>
static FILE *handles[6];

int io_open(char *name, int length)
{
    int i;
    char filename[300];
    if (length < 0 || length > 290) return -2;
    memcpy(filename, name, (size_t)length);
    filename[length] = 0;
    i = 1;
    while (i <= 5) {
        if (handles[i] == NULL) {
            handles[i] = fopen(filename, "rb");
            if (handles[i] != NULL) return i;
            return -2;
        }
        i = i + 1;
    }
    return -2;
}

int io_read(int handle)
{
    int c;
    if (handle < 1 || handle > 5 || handles[handle] == NULL) return -2;
    c = fgetc(handles[handle]);
    if (c == EOF) return -1;
    return c;
}

char io_close(int handle)
{
    if (handle < 1 || handle > 5 || handles[handle] == NULL) return 1;
    fclose(handles[handle]);
    handles[handle] = NULL;
    return 0;
}

#if NATIVE_ALGORITHM
#include "../../bootstrap/ass_native.c"
#else
#include "../../bootstrap/ass.c"
#endif
