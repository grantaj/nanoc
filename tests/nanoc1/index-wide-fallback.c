/* A char array can be larger than 256 bytes. An int/unsigned index
 * must retain its high byte: absolute,Y would wrap to offsets 0 and 1. */
char bytes[260];

int main()
{
    int i = 256;
    unsigned j = 257;
    char a = 0;
    char b = 0;

    bytes[0] = 'q';
    bytes[1] = 'r';
    bytes[i] = 'A';
    bytes[j] = 'B';

    a = bytes[i];
    b = bytes[j];
    if (a == 'A') {
        if (b == 'B') {
            if (bytes[0] == 'q') {
                if (bytes[1] == 'r') {
                    return 'Z';
                }
            }
        }
    }
    return 0;
}
