/* Real Phase-1 condition expressions using the already-supported
 * left-associated arithmetic tape, not a new expression parser.
 * Each function is benchmarked against nanoc1 from identical C source.
 */
char expr_marks[256];

int expr_less(int left, int right, int limit)
{
    if (left + right < limit) { return 1; }
    return 0;
}

int expr_ge_byte(int left, char offset, int limit)
{
    if (left + offset >= limit) { return 1; }
    return 0;
}

int expr_chain_equal(unsigned left, char offset)
{
    if (left + offset + 1 == 256) { return 1; }
    return 0;
}

int expr_chain_truth(char value)
{
    if (value + 1) { return 1; }
    return 0;
}

int expr_difference_truth(unsigned left, unsigned right)
{
    if (left - right) { return 1; }
    return 0;
}

int expr_reversed_byte(char offset, unsigned left, unsigned limit)
{
    if (offset + left < limit) { return 1; }
    return 0;
}

int expr_compare_byte(unsigned left, char offset, char limit)
{
    if (left + offset <= limit) { return 1; }
    return 0;
}

int expr_count_down(unsigned value)
{
    unsigned seen;
    seen = 0;
    while (value - 1) {
        value = value - 1;
        seen = seen + 1;
    }
    return seen;
}

int expr_index_until(char limit)
{
    char i;
    i = 0;
    while (i + 1 < limit) {
        expr_marks[i] = i;
        i = i + 1;
    }
    return i;
}
