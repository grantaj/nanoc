char pad[250] = "x";
char bytes[8] = "abcdefg";
int words[3] = {1, 4660, 32767};
char byte_value = 255;

int main()
{
    int r00 = 0;
    int r01 = 32767;
    unsigned r02 = 32768;
    unsigned r03 = 65535;
    int r04 = byte_value;
    int r05 = 65535 + 2;
    int r06 = 0 - 1;
    int r07 = 2 + 3 * 4;
    int r08 = (2 + 3) * 4;
    int r09 = 1 + 2 << 3;
    int r10 = 1 << 2 + 1;
    int r11 = 1 & 2 == 2;
    int r12 = 3855 & 255 | 4096;
    int r13 = -5 + 2;
    int r14 = 1 << 0;
    int r15 = 1 << 15;
    unsigned r16 = 65535 >> 15;
    int r17 = (-32767 - 1) < -1;
    int r18 = -1 > 0;
    int r19 = 32767 < (-32767 - 1);
    int r20 = (-32767 - 1) < 32767;
    int r21 = 32767 < 32768;
    int r22 = 32768 < 65535;
    int r23 = 65535 > 32768;
    char *p = bytes + 63233;
    char *q = p + 3;
    int r26 = bytes[4];
    int r27 = words[1];
    int r28 = ('A' == 65) & (5 != 6);
    int r29 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"[70];
}
