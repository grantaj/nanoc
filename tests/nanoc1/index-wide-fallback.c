/* A char array can be larger than 256 bytes. An int/unsigned index
 * must retain its high byte: absolute,Y would wrap to offsets 0 and 1. */
char bytes[260];

int main()
{
    int i = 256;
    unsigned j = 257;
    int zero = 0;
    int one = 1;
    char a = 0;
    char b = 0;

    bytes[zero] = 'q';
    bytes[one] = 'r';
    bytes[i] = 'A';
    bytes[j] = 'B';

    a = bytes[i];
    b = bytes[j];
    if (a == 'A') {
        if (b == 'B') {
            if (bytes[zero] == 'q') {
                if (bytes[one] == 'r') {
                    return 'Z';
                }
            }
        }
    }
    return 0;
}
