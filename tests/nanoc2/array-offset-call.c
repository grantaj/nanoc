/* Native Phase-1 calls taking a char array plus a scalar offset.
 * Array decay uses the linker address, then full 16-bit carry arithmetic.
 * A pointer variable uses its distinct two-byte static parameter home.
 */
char offset_bytes[640];

char offset_fetch(char *data, char index)
{
    return data[index];
}

char offset_from_byte(char start)
{
    return offset_fetch(offset_bytes + start, 1);
}

char offset_from_word(unsigned start)
{
    return offset_fetch(offset_bytes + start, 1);
}

char offset_from_literal()
{
    return offset_fetch(offset_bytes + 255, 1);
}

char offset_from_pointer(char *data, char start)
{
    return offset_fetch(data + start, 1);
}
