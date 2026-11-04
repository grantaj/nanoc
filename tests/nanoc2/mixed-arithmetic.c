/* Mixed-width and left-associated arithmetic in original Phase-1 C.
 * All operands are pure scalars/literals; expressions may read their
 * destination late, so the compiler must not overwrite it early.
 */
int widen_copy(char small)
{
    int out;
    out = small;
    return out;
}

char narrow_copy(int wide)
{
    char out;
    out = wide;
    return out;
}

int widen_return(char small)
{
    return small;
}

char narrow_return(int wide)
{
    return wide;
}

int mix_add(int wide, char delta)
{
    int out;
    out = wide + delta;
    return out;
}

int mix_sub(int wide, char delta)
{
    int out;
    out = wide - delta;
    return out;
}

int mix_return(int wide, char delta)
{
    return wide + delta;
}

int mix_return_sub(int wide, char delta)
{
    return wide - delta;
}

int compound(int left, int right, char offset)
{
    int out;
    out = left + right - offset + 257;
    return out;
}

int compound_return(int left, int right, char offset)
{
    return left + right - offset + 257;
}

int reverse_mixed(char delta, int wide)
{
    return delta + wide;
}

int literal_base(int wide, char delta)
{
    return 1 + wide - delta;
}

int reverse_sub(char delta, int wide)
{
    return delta - wide;
}

int alias_late(int wide, char delta)
{
    wide = wide + delta + wide;
    return wide;
}

char byte_chain(char left, char right)
{
    char out;
    out = left + right + 1;
    return out;
}

char byte_return(char left, char right)
{
    return left + right + 1;
}

int byte_sum_word(char left, char right)
{
    return left + right;
}

/* Direct two-operand variants keep a record of the cases where the
 * initial generic accumulator path produced larger code than nanoc1. */
int reverse_add_store(char delta, int wide)
{
    int out;
    out = delta + wide;
    return out;
}

int reverse_sub_store(char delta, int wide)
{
    int out;
    out = delta - wide;
    return out;
}

int byte_sum_store(char left, char right)
{
    int out;
    out = left + right;
    return out;
}

char byte_pair_return(char left, char right)
{
    return left + right;
}

char byte_pair_store(char left, char right)
{
    char out;
    out = left + right;
    return out;
}
