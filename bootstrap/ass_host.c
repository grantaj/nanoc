#include <stdio.h>
#include <string.h>

FILE *host_files[8];

int io_open(char *name, int length)
{
    char path[256];
    int i;
    int slot;

    if (length <= 0 || length >= 256) {
        return -1;
    }

    i = 0;
    while (i < length) {
        path[i] = name[i];
        i = i + 1;
    }
    path[length] = 0;

    slot = 0;
    while (slot < 8) {
        if (host_files[slot] == NULL) {
            host_files[slot] = fopen(path, "rb");
            if (host_files[slot] == NULL) {
                return -1;
            }
            return slot;
        }
        slot = slot + 1;
    }
    return -1;
}

int io_read(int handle)
{
    int c;

    c = fgetc(host_files[handle]);
    if (c == EOF) {
        if (ferror(host_files[handle])) {
            return -2;
        }
        return -1;
    }
    return c;
}

int io_close(int handle)
{
    if (host_files[handle] != NULL) {
        fclose(host_files[handle]);
        host_files[handle] = NULL;
    }
    return 0;
}

#include "ass.c"

int write_prg(char *name)
{
    FILE *output;
    int i;

    output = fopen(name, "wb");
    if (output == NULL) {
        return 1;
    }

    fputc(ass_origin & 255, output);
    fputc((ass_origin >> 8) & 255, output);

    i = 0;
    while (i < ass_image_length) {
        fputc(ass_image[i], output);
        i = i + 1;
    }

    if (fclose(output) != 0) {
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    int status;
    char *directory;
    int directory_length;

    if (argc != 4) {
        fprintf(stderr, "usage: %s source output source-directory\n", argv[0]);
        return 2;
    }

    directory = argv[3];
    directory_length = (int)strlen(directory);

    status = ass_assemble(
        argv[1],
        (int)strlen(argv[1]),
        directory,
        directory_length,
        0
    );
    if (status != ASSEMBLE_OK) {
        fprintf(stderr, "assembly failed: status %d\n", status);
        return 1;
    }

    if (write_prg(argv[2]) != 0) {
        fprintf(stderr, "could not write %s\n", argv[2]);
        return 1;
    }

    return 0;
}
