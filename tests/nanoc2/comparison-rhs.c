/* Full promoted integer arithmetic on the right side of conditions.
 * These routines use the same Phase-1 C parser and emitter as ass.c.
 * No source-specific lowering or host-only production implementation.
 */
char rhs_lt(char value, char limit)
{
    if (value < limit - 1) return 1;
    return 0;
}

char rhs_le(char value, char limit)
{
    if (value <= limit - 1) return 1;
    return 0;
}

char rhs_gt(char value, char limit)
{
    if (value > limit - 1) return 1;
    return 0;
}

char rhs_ge(char value, char limit)
{
    if (value >= limit - 1) return 1;
    return 0;
}

char rhs_eq(char value, char limit)
{
    if (value == limit - 1) return 1;
    return 0;
}

char rhs_ne(char value, char limit)
{
    if (value != limit - 1) return 1;
    return 0;
}

char rhs_signed(int value, int limit)
{
    if (value < limit - 1) return 1;
    return 0;
}

char rhs_unsigned(unsigned value, unsigned limit)
{
    if (value < limit - 1) return 1;
    return 0;
}

char rhs_literal(int limit)
{
    if (255 < limit - 1) return 1;
    return 0;
}

char rhs_chain(char value, char limit, char offset)
{
    if (value < limit - offset + 1) return 1;
    return 0;
}
