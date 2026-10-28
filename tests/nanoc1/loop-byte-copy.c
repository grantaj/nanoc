/* #102 bounded semantic region: the loop index must live in Y and carry
 * around the back-edge without an array-address reconstruction. */
char src[8] = {3, 5, 7, 9, 11, 13, 15, 17};
char dst[8];
char i = 1;
char n = 6;

int main()
{
    while (i < n) {
        dst[i] = src[i];
        i = i + 1;
    }
    if (i == 6) {
        if (dst[1] == 5) {
            if (dst[5] == 13) {
                return 'Z';
            }
        }
    }
    return 0;
}
