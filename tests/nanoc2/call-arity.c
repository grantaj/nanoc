/* Exercise genuine Phase-1 call argument count, static ABI staging and
 * result sequencing through the single original-parser traversal path.
 * The two-argument function checks both argument slots, and main calls
 * it within a live X-indexed loop. No 16-bit operations are required.
 */
char call_source[256];
char call_dest[256];

char constant()
{
    return 90;
}

char guarded(char value, char sentinel)
{
    if (sentinel != 90) {
        return 0;
    }
    return value;
}

char main()
{
    char i;
    i = 0;
    while (i < 200) {
        call_dest[i] = guarded(call_source[i], 90);
        i = i + 1;
    }
    return constant();
}
