char bytes[2];

int main()
{
    char *p;

    p = bytes + 0;
    bytes[0] = p;
    return 0;
}
