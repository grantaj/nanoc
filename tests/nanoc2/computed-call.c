/* Pure, typed argument expressions to real two-argument Phase-1 calls.
 * These stage parameters in source order before the JSR. No optimizer,
 * recursive expression visitor, or expression reordering is required.
 */
int combine_word(int left, int right)
{
    return left + right;
}

int computed_call(int a, int b)
{
    return combine_word(a, (a + b + 1) & 65535);
}

int two_computed(int a, int b)
{
    return combine_word(a + b, b - a);
}

int wrapped_args(int a, int b)
{
    return combine_word((a + 65535) & 65535,
                        (b + 1) & 65535);
}

int mixed_args(int a, char b)
{
    return combine_word(a + b, (a - b + 257) & 65535);
}
