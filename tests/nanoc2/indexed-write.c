/* Phase-1 byte-indexed store fixtures. Compiled by the same parser and GCC.
 * These are independent source examples, not hand-entered operation tapes.
 */
char source_bytes[256];
char dest_bytes[256];

char copy_pointer(char *dst, char *src, char n)
{
    char i;
    i = 0;
    while (i < n) {
        dst[i] = src[i];
        i = i + 1;
    }
    return i;
}

char fill_pointer(char *dst, char n, char value)
{
    char i;
    i = 0;
    while (i < n) {
        dst[i] = value;
        i = i + 1;
    }
    return i;
}

char clear_pointer(char *dst, char n)
{
    char i;
    i = 0;
    while (i < n) {
        dst[i] = 0;
        i = i + 1;
    }
    return i;
}

char copy_array(char n)
{
    char i;
    i = 0;
    while (i < n) {
        dest_bytes[i] = source_bytes[i];
        i = i + 1;
    }
    return i;
}

char fill_array(char n, char value)
{
    char i;
    i = 0;
    while (i < n) {
        dest_bytes[i] = value;
        i = i + 1;
    }
    return i;
}
