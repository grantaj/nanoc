/* The byte cursor is live through the back edge. Both arrays cross pages. */
char padding[251];
char src[8] = {2, 4, 6, 8, 10, 12, 14, 16};
char dst[8];
char i = 0;
char n = 7;

int main()
{
    i = 0;
    while (i < n) {
        dst[i] = src[i];
        i = 1 + i;
    }
    if (i != 7) {
        return 1;
    }
    if (dst[0] != 2) {
        return 2;
    }
    if (dst[3] != 8) {
        return 3;
    }
    if (dst[6] != 14) {
        return 4;
    }
    if (dst[7] != 0) {
        return 5;
    }

    /* Non-matching loops must replay through the original parser. */
    i = 0;
    while (i < 3) {
        i = i + 1;
    }
    if (i != 3) {
        return 6;
    }
    return 'Z';
}
