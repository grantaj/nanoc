/* Pointer operands may cross a page; mismatch must return early. */
char padding[251];
char left[256];
char right[256];

char same_bytes(char *a, char *b, char n)
{
    char i = 0;
    while (i < n) {
        if (a[i] != b[i]) {
            return 0;
        }
        i = i + 1;
    }
    return 1;
}

int main()
{
    char i = 0;

    while (i < 255) {
        left[i] = i;
        right[i] = i;
        i = i + 1;
    }
    if (same_bytes(left, right, 255) != 1) {
        return 1;
    }
    right[254] = 13;
    if (same_bytes(left, right, 255) != 0) {
        return 2;
    }
    right[254] = 254;
    if (same_bytes(left, right, 255) != 1) {
        return 3;
    }
    right[0] = 17;
    if (same_bytes(left, right, 0) != 1) {
        return 4;
    }
    if (same_bytes(left, right, 255) != 0) {
        return 5;
    }
    return 90;
}
