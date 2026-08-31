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
}
