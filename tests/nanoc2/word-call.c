/* Word and byte call ABI: static Nano C argument homes, A/X returns. */
char out_bytes[8];

int seed()
{
    return 4660;
}

int pass_one(int value)
{
    return value;
}

int add_pair(int left, int right)
{
    return left + right;
}

int word_relay(int value)
{
    return pass_one(value);
}

int pair_relay(int left, int right)
{
    int tmp;
    tmp = add_pair(left, right);
    return pass_one(tmp);
}

int const_pair()
{
    return add_pair(4660, 1);
}

char echo_byte(char value)
{
    return value;
}

int byte_to_word(char value)
{
    return pass_one(value);
}

int word_to_byte(int value)
{
    return echo_byte(value);
}

int byte_to_word_store(int value)
{
    int out;
    out = echo_byte(value);
    return out;
}

int mixed_pair(int left, char tag)
{
    return left;
}

int mixed_relay(int left, char tag)
{
    return mixed_pair(left, tag);
}

int indexed_word_call(char i)
{
    int tmp;
    tmp = 0;
    while (i < 3) {
        out_bytes[i] = i;
        tmp = pass_one(4660);
        i = i + 1;
    }
    return tmp;
}
