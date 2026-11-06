/* Indexed char array reads passed to a word parameter promote the
 * byte to a 16-bit unsigned value. Both byte- and word-width indexes
 * must preserve their real machine address, including page crossings.
 */
char promoted_bytes[640];

int accept_promoted_word(int value)
{
    return value;
}

int promoted_byte_index(char offset)
{
    return accept_promoted_word(promoted_bytes[offset]);
}

int promoted_word_index(unsigned offset)
{
    return accept_promoted_word(promoted_bytes[offset]);
}
