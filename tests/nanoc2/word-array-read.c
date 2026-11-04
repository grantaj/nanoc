/* Verbatim C semantics, not special 6502 instruction templates.
 * Exercise word-array indexing with both element stride and C width
 * preserved in return, store and signed/unsigned comparisons.
 */
unsigned word_samples[640];

int read_sample(int index)
{
    return word_samples[index];
}

int copy_sample(int index)
{
    int value;
    value = word_samples[index];
    return value;
}

int sample_equals(int index, int expected)
{
    if (word_samples[index] == expected) {
        return 1;
    }
    return 0;
}

int read_previous_sample(int index)
{
    return word_samples[index - 1];
}
