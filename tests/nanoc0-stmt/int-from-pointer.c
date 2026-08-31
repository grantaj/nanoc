char bytes[2];
int global_value;

int main()
{
    char *p;

    p = bytes + 0;
    global_value = p;
    return 0;
}
