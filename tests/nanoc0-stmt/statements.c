char bytes[300];
int words[140];
unsigned uwords[140];
char global_char;
int global_value;
unsigned global_unsigned;
char *global_pointer;
int call_order;

int add_pair(int a, int b)
{
    return a + b;
}

int return_one()
{
    return 1;
}

int mark_arg(int expected, int value)
{
    if (call_order != expected) {
        return 30000;
    }
    call_order = call_order + 1;
    return value;
}

int take_char(char value)
{
    return value;
}

int take_unsigned(unsigned value)
{
    return value;
}

int take_pointer(char *value)
{
    return value[1];
}

int main()
{
    char c;
    char bi;
    int x;
    unsigned u;
    char *p;
    int i;
    int j;
    int sum;
    int outer;
    int marker;

    call_order = 0;
    marker = add_pair(mark_arg(0, 1), mark_arg(1, 2));
    if (marker != 3) {
        return 100;
    }
    if (call_order != 2) {
        return 101;
    }

    if (add_pair(3, add_pair(4, 5)) != 12) {
        return 102;
    }
    if (add_pair(return_one(), return_one()) != 2) {
        return 103;
    }
    if (5 + add_pair(1, 2) != 8) {
        return 104;
    }

    return_one();
    if (return_one() != 1) {
        return 105;
    }
    if (take_char(4660) != 52) {
        return 106;
    }
    if (take_unsigned(4660) != 4660) {
        return 107;
    }
    if (take_pointer("AZ") != 'Z') {
        return 108;
    }

    global_char = 511;
    if (global_char != 255) {
        return 1;
    }

    global_value = 4660;
    if (global_value != 4660) {
        return 2;
    }

    global_unsigned = 65535;
    if (global_unsigned != 65535) {
        return 3;
    }

    global_pointer = bytes + 255;
    global_pointer[1] = 90;
    if (bytes[256] != 90) {
        return 4;
    }

    c = 511;
    if (c != 255) {
        return 5;
    }

    marker = 0;
    global_char = 7;
    c = 9;
    if (global_char == c) {
        return 30;
    }
    if (global_char != c) {
        marker = marker + 1;
    } else {
        return 31;
    }
    if (global_char < c) {
        marker = marker + 1;
    } else {
        return 32;
    }
    if (global_char <= c) {
        marker = marker + 1;
    } else {
        return 33;
    }
    if (global_char > c) {
        return 34;
    }
    if (global_char >= c) {
        return 35;
    }

    c = 7;
    if (global_char != c) {
        return 36;
    }
    if (global_char == c) {
        marker = marker + 1;
    } else {
        return 37;
    }
    if (global_char <= c) {
        marker = marker + 1;
    } else {
        return 38;
    }
    if (global_char >= c) {
        marker = marker + 1;
    } else {
        return 39;
    }
    if (global_char < c) {
        return 40;
    }
    if (global_char > c) {
        return 41;
    }
    if (marker != 6) {
        return 42;
    }

    c = 0;
    if (c) {
        return 43;
    }
    if (c != 0) {
        return 44;
    }
    if (c < 0) {
        return 45;
    }
    if (c <= 0) {
        marker = marker + 1;
    } else {
        return 46;
    }
    if (c > 0) {
        return 47;
    }
    if (c >= 0) {
        marker = marker + 1;
    } else {
        return 48;
    }

    c = 255;
    if (c == 255) {
        marker = marker + 1;
    } else {
        return 49;
    }
    if (c != 255) {
        return 50;
    }
    if (c > 255) {
        return 51;
    }
    if (c <= 255) {
        marker = marker + 1;
    } else {
        return 52;
    }
    if (c < 255) {
        return 53;
    }
    if (c >= 255) {
        marker = marker + 1;
    } else {
        return 54;
    }
    if (c) {
        marker = marker + 1;
    } else {
        return 55;
    }

    c = 7;
    if (c >= 8) {
        return 56;
    }
    if (c < 8) {
        marker = marker + 1;
    } else {
        return 57;
    }
    if (c > 6) {
        marker = marker + 1;
    } else {
        return 58;
    }
    if (c <= 6) {
        return 59;
    }

    global_char = 9;
    x = (c < global_char) + 300;
    if (x != 301) {
        return 60;
    }

    x = -1;
    if (x >= 0) {
        return 61;
    }
    if (x < 0) {
        marker = marker + 1;
    } else {
        return 62;
    }

    u = 65535;
    if (u <= 255) {
        return 63;
    }
    if (u > 255) {
        marker = marker + 1;
    } else {
        return 64;
    }

    x = 4660;
    if (x != 4660) {
        return 6;
    }

    u = 65535;
    if (u != 65535) {
        return 7;
    }

    p = bytes + 256;
    p[1] = 91;
    if (bytes[257] != 91) {
        return 8;
    }

    /* #73: byte indexes should look like native 6502 indexing, not address math. */
    bi = 3;
    bytes[bi] = 93;
    if (bytes[bi] != 93) {
        return 109;
    }

    p = bytes + 240;
    bi = 7;
    p[bi] = take_char(94);
    if (p[bi] != 94) {
        return 110;
    }

    /* Literal and genuine 16-bit indexes retain the explicit fallback. */
    bytes[4] = 95;
    if (bytes[4] != 95) {
        return 111;
    }
    p = bytes;
    i = 259;
    p[i] = 96;
    if (bytes[259] != 96) {
        return 112;
    }

    /* A call in a wide index must not lose the pointer value captured first. */
    global_pointer = bytes + 250;
    bytes[251] = 97;
    if (global_pointer[return_one()] != 97) {
        return 113;
    }

    /* The saved byte index must also survive a nontrivial RHS with a call. */
    bi = 5;
    bytes[bi] = bytes[4] + return_one();
    if (bytes[bi] != 96) {
        return 114;
    }

    /* Nested indexing must preserve the outer fixed-array marker. */
    bytes[1] = 4;
    bytes[4] = 98;
    if (bytes[bytes[1]] != 98) {
        return 115;
    }

    bytes[258] = bytes[257] + 1;
    if (bytes[258] != 92) {
        return 9;
    }

    words[129] = 4660;
    if (words[129] != 4660) {
        return 10;
    }

    uwords[129] = 65535;
    if (uwords[129] != 65535) {
        return 11;
    }

    marker = 0;
    if (0) {
        marker = 1;
    } else {
        marker = 2;
    }
    if (marker != 2) {
        return 12;
    }

    if (4660) {
        marker = 3;
    } else {
        marker = 4;
    }
    if (marker != 3) {
        return 13;
    }

    if (1) {
        if (0) {
            marker = 4;
        } else {
            marker = 5;
        }
    } else {
        marker = 6;
    }
    if (marker != 5) {
        return 14;
    }

    marker = 0;
    if (1) {
        marker = 6;
    }
    if (marker != 6) {
        return 15;
    }
    if (0) {
        marker = 99;
    }
    if (marker != 6) {
        return 16;
    }

    i = 0;
    sum = 0;
    while (i < 5) {
        sum = sum + i;
        i = i + 1;
    }
    if (sum != 10) {
        return 17;
    }

    i = 0;
    while (0) {
        i = 99;
    }
    if (i != 0) {
        return 18;
    }

    i = 0;
    outer = 0;
    while (i < 3) {
        j = 0;
        while (1) {
            j = j + 1;
            break;
            j = 99;
        }
        outer = outer + j;
        i = i + 1;
    }
    if (outer != 3) {
        return 19;
    }

    u = 65534;
    i = 0;
    while (u != 1) {
        u = u + 1;
        i = i + 1;
    }
    if (i != 3) {
        return 20;
    }

    marker = 0;
    {
        {
            {
                {
                    {
                        {
                            {
                                {
                                    {
                                        {
                                            {
                                                {
                                                    {
                                                        {
                                                            {
                                                                {
                                                                    marker = marker + 1;
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (marker != 1) {
        return 21;
    }

    marker = 0;
    if (0) {
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
    } else {
        marker = 7;
    }
    if (marker != 7) {
        return 22;
    }

    while (0) {
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
        x = x + 1;
    }
    marker = 8;
    if (marker != 8) {
        return 23;
    }

    while (1) {
        if (marker == 8) {
            return 4660;
        } else {
            return 24;
        }
    }

    return 25;
}
