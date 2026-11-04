/* The first direct 16-bit Nano C emitter slice.
 * All operations use actual Phase-1 int slots and return low in A, high in X.
 * No generic arithmetic or call-lowering fallback is used.
 */
int target;

int constant_word()
{
    return 4660;
}

int echo_word(int value)
{
    return value;
}

int add_word(int value)
{
    int local;
    local = value + 255;
    return local + 1;
}

int subtract_word(int value)
{
    int local;
    local = value - 257;
    return local - 1;
}

int main()
{
    int local;
    local = 4660;
    target = local;
    return target;
}
