char bytes[256];

int main()
{
    char i = 0;
    char high = 200;
    int total = 0;

    bytes[high] = 13;
    while (i < 5) {
        bytes[i] = i + 1;
        if (bytes[i] > 0) {
            total = total + bytes[i];
        }
        i = i + 1;
    }
    if (bytes[high] == 13) {
        if (total == 15) {
            return 'Z';
        }
    }
    return 0;
}
