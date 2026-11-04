/* General two-byte arithmetic and typed comparison tests for nanoc2.
 * One source unit, many static Nano C function/parameter homes. All values
 * are supplied by the independent 6510 test caller; no host-only parser.
 */
int sum_word(int left, int right)
{
    int out;
    out = left + right;
    return out;
}
int diff_word(int left, int right)
{
    int out;
    out = left - right;
    return out;
}
int inplace_sum_left(int left, int right)
{
    left = left + right;
    return left;
}
int inplace_sum_right(int left, int right)
{
    right = left + right;
    return right;
}
int inplace_diff_left(int left, int right)
{
    left = left - right;
    return left;
}
int inplace_diff_right(int left, int right)
{
    right = left - right;
    return right;
}
int return_sum(int left, int right)
{
    return left + right;
}
int return_diff(int left, int right)
{
    return left - right;
}
int signed_lt(int left, int right)
{
    if (left < right) return 1;
    return 0;
}
int signed_le(int left, int right)
{
    if (left <= right) return 1;
    return 0;
}
int signed_gt(int left, int right)
{
    if (left > right) return 1;
    return 0;
}
int signed_ge(int left, int right)
{
    if (left >= right) return 1;
    return 0;
}
int signed_eq(int left, int right)
{
    if (left == right) return 1;
    return 0;
}
int signed_ne(int left, int right)
{
    if (left != right) return 1;
    return 0;
}
int unsigned_lt(unsigned left, unsigned right)
{
    if (left < right) return 1;
    return 0;
}
int unsigned_le(unsigned left, unsigned right)
{
    if (left <= right) return 1;
    return 0;
}
int unsigned_gt(unsigned left, unsigned right)
{
    if (left > right) return 1;
    return 0;
}
int unsigned_ge(unsigned left, unsigned right)
{
    if (left >= right) return 1;
    return 0;
}
int unsigned_eq(unsigned left, unsigned right)
{
    if (left == right) return 1;
    return 0;
}
int unsigned_ne(unsigned left, unsigned right)
{
    if (left != right) return 1;
    return 0;
}
int mixed_gt(int left, unsigned right)
{
    if (left > right) return 1;
    return 0;
}
int signed_const_lt(int left)
{
    if (left < 256) return 1;
    return 0;
}
int unsigned_const_gt(unsigned left)
{
    if (left > 32768) return 1;
    return 0;
}
int word_truth(unsigned left)
{
    if (left) return 1;
    return 0;
}
int word_count(unsigned left)
{
    unsigned result;
    result = 0;
    while (left) {
        left = left - 1;
        result = result + 1;
    }
    return result;
}
