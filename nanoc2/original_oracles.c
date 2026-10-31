/* Source-equivalent unchanged algorithm bodies from nanoc1/nanoc1.c. */
char global_name[5632];
char global_name_len[176];
char token_text[192];
char token_length;
char global_count;

char same_bytes(char *a, char a_length, char *b, char b_length)
{
    char i;
    if (a_length != b_length) return 0;
    i = 0;
    while (i < a_length) {
        if (a[i] != b[i]) return 0;
        i = i + 1;
    }
    return 1;
}

char find_global()
{
    char symbol;
    char i;
    int base;
    char match;
    symbol = 0;
    while (symbol < global_count) {
        if (global_name_len[symbol] == token_length) {
            base = symbol * 32;
            i = 0;
            match = 1;
            while (i < token_length) {
                if (global_name[base + i] != token_text[i]) {
                    match = 0;
                    break;
                }
                i = i + 1;
            }
            if (match != 0) return symbol;
        }
        symbol = symbol + 1;
    }
    return 255;
}
