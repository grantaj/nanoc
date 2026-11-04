/* Mixed C integer-width comparisons. The original Phase-1 parser
 * decides the common signedness; the emitter must compare both bytes,
 * preserving C/Z flags and live X/Y byte-induction registers.
 */
char compare_marks[256];

int mix_lt(int word, char byte)
{
    if (word < byte) { return 1; }
    return 0;
}

int rev_lt(char byte, int word)
{
    if (byte < word) { return 1; }
    return 0;
}

int umix_lt(unsigned word, char byte)
{
    if (word < byte) { return 1; }
    return 0;
}

int urev_lt(char byte, unsigned word)
{
    if (byte < word) { return 1; }
    return 0;
}

int mix_le(int word, char byte)
{
    if (word <= byte) { return 1; }
    return 0;
}

int rev_le(char byte, int word)
{
    if (byte <= word) { return 1; }
    return 0;
}

int umix_le(unsigned word, char byte)
{
    if (word <= byte) { return 1; }
    return 0;
}

int urev_le(char byte, unsigned word)
{
    if (byte <= word) { return 1; }
    return 0;
}

int mix_gt(int word, char byte)
{
    if (word > byte) { return 1; }
    return 0;
}

int rev_gt(char byte, int word)
{
    if (byte > word) { return 1; }
    return 0;
}

int umix_gt(unsigned word, char byte)
{
    if (word > byte) { return 1; }
    return 0;
}

int urev_gt(char byte, unsigned word)
{
    if (byte > word) { return 1; }
    return 0;
}

int mix_ge(int word, char byte)
{
    if (word >= byte) { return 1; }
    return 0;
}

int rev_ge(char byte, int word)
{
    if (byte >= word) { return 1; }
    return 0;
}

int umix_ge(unsigned word, char byte)
{
    if (word >= byte) { return 1; }
    return 0;
}

int urev_ge(char byte, unsigned word)
{
    if (byte >= word) { return 1; }
    return 0;
}

int mix_eq(int word, char byte)
{
    if (word == byte) { return 1; }
    return 0;
}

int rev_eq(char byte, int word)
{
    if (byte == word) { return 1; }
    return 0;
}

int umix_eq(unsigned word, char byte)
{
    if (word == byte) { return 1; }
    return 0;
}

int urev_eq(char byte, unsigned word)
{
    if (byte == word) { return 1; }
    return 0;
}

int mix_ne(int word, char byte)
{
    if (word != byte) { return 1; }
    return 0;
}

int rev_ne(char byte, int word)
{
    if (byte != word) { return 1; }
    return 0;
}

int umix_ne(unsigned word, char byte)
{
    if (word != byte) { return 1; }
    return 0;
}

int urev_ne(char byte, unsigned word)
{
    if (byte != word) { return 1; }
    return 0;
}

int byte_lt_256(char byte)
{
    if (byte < 256) { return 1; }
    return 0;
}

int byte_eq_256(char byte)
{
    if (byte == 256) { return 1; }
    return 0;
}

int literal_gt_byte(char byte)
{
    if (256 > byte) { return 1; }
    return 0;
}

int literal_eq_byte(char byte)
{
    if (255 == byte) { return 1; }
    return 0;
}

int literal_lt_word(int word)
{
    if (256 < word) { return 1; }
    return 0;
}

int literal_eq_word(int word)
{
    if (256 == word) { return 1; }
    return 0;
}

int literal_gt_unsigned(unsigned word)
{
    if (256 > word) { return 1; }
    return 0;
}

int byte_ge_257(char byte)
{
    if (byte >= 257) { return 1; }
    return 0;
}

int word_lt_byte_literal(int word)
{
    if (word < 255) { return 1; }
    return 0;
}

/* Nonzero byte index is held in X by the traversal planner; neither
 * side of the mixed comparison may read its outdated static home. */
int mark_below_word(int limit)
{
    char i;
    i = 0;
    while (i < limit) {
        compare_marks[i] = i;
        i = i + 1;
    }
    return i;
}

int advance_word_until_byte(int start, char limit)
{
    while (start < limit) {
        start = start + 1;
    }
    return start;
}
