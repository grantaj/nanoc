/* A non-matching loop must compile through the ordinary emitter even when
 * the semantic probe has already consumed the entire source region. */
char src[8] = {3, 5, 7, 9, 11, 13, 15, 17};
char dst[8];
char i = 1;
char n = 6;

int main()
{
    while (i < n) {
        dst[i] = src[i] + 1;
        i = i + 1;
    }
    if (i == 6) {
        if (dst[1] == 6) {
            if (dst[5] == 14) {
                return 'Z';
            }
        }
    }
    return 0;
}
