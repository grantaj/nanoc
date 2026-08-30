char flag;
int count;
unsigned address;
char *source;
char c = 'A';
int neg = -1;
unsigned u = 0xc000;
char bytes[4];
int words[2];
unsigned addresses[2];
char widths[4] = {0, 1};
unsigned table[3] = {0x4000, 0xc000, 0xffff};
char text[5] = "abc";
int helper(char p, unsigned q, char *s)
{
    int a;
    int b = p;
    unsigned c = q + address;
    int input = io_read(0);
    int d = b;
    io_write(0, input);
    return b;
}
int main()
{
    int x;
    x = helper(flag, address, source);
    return x;
}
