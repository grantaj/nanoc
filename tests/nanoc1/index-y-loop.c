/* Force bytes to begin late on a page: an index of 200 must carry. */
char padding[220];
char bytes[256];

int main()
{
    char i = 0;
    char high = 200;
    char readback = 0;
    int total = 0;

    bytes[high] = 13;
    while (i < 5) {
        bytes[i] = i + 1;
        if (bytes[i] > 0) {
            total = total + bytes[i];
        }
        i = i + 1;
    }
    readback = bytes[high];
    if (readback == 13) {
        if (total == 15) {
            return 'Z';
        }
    }
    return 0;
}
