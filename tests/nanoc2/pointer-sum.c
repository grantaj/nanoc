/* Pointer indices are full C arithmetic, not an 8-bit Y offset.
 * The second routine also shares a ZP cursor with a wide-array access,
 * and then deliberately reuses the second pointer after that access.
 */
char mixed_marks[640];

char pointer_sum_read(char *data, char left, char right)
{
    return data[left + right];
}

char pointer_sum_store(char *data, char left, char right, char value)
{
    data[left + right] = value;
    return data[left + right];
}

char pointer_mix(char *first, char *second, unsigned where,
                 char left, char right)
{
    char ignored;
    ignored = first[0];
    mixed_marks[where] = second[left + right];
    return second[left];
}
