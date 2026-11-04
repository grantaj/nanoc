/* The original Phase-1 parser owns both functions. The caller keeps its
 * array index in X while the callee returns through A/X.
 * An identity helper isolates call convention and register reconciliation
 * without requiring 16-bit arithmetic or new expression operators.
 */
char call_source[256];
char call_dest[256];

char identity(char value)
{
    return value;
}

char main()
{
    char i;
    i = 0;
    while (i < 200) {
        call_dest[i] = identity(call_source[i]);
        i = i + 1;
    }
    return i;
}
