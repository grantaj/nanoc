char bytes[300];
int words[140];
unsigned uwords[140];
char global_char;
int global_value;
unsigned global_unsigned;
char *global_pointer;

int main()
{
    char c;
    int x;
    unsigned u;
    char *p;
    int i;
    int j;
    int sum;
    int outer;
    int marker;

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
