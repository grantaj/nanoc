/* The original Phase-1 parser owns both functions. The caller keeps its
 * array index in X while the callee returns through A/X.
 * A non-identity helper checks that its actual A return value (not the
 * input argument) reaches the indexed destination after restoring X.
 */
char call_source[256];
char call_dest[256];

char map_byte(char value)
{
    if (value == 0) {
        return 17;
    }
    return 34;
}

char main()
{
    char i;
    i = 0;
    while (i < 200) {
        call_dest[i] = map_byte(call_source[i]);
        i = i + 1;
    }
    return i;
}
