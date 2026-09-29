char table[4] = {1, 2, 3, 4};

char add_one(char value)
{
    return value + 1;
}

int main()
{
    char i = 0;
    int total = 0;

    while (i < 4) {
        total = total + table[i];
        i = add_one(i);
    }
    table[1 + 1] = total;
    if (table[2] == 10) {
        return 'Z';
    } else {
        return 'N';
    }
}