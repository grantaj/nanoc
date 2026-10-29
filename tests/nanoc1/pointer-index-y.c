/* Byte pointer-index loads must use (zp),Y, wide indexes must not wrap. */
char padding[220];
char bytes[300];

int main()
{
    char *p = bytes;
    char small = 200;
    int wide = 256;

    p[small] = 'Q';
    p[wide] = 'R';
    if (p[small] != 'Q') {
        return 1;
    }
    if (p[wide] != 'R') {
        return 2;
    }
    if (bytes[200] != 'Q') {
        return 3;
    }
    if (bytes[256] != 'R') {
        return 4;
    }
    return 90;
}
