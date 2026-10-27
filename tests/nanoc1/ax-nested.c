char box[3] = {10, 20, 30};

int add(int a, int b)
{
    return a + b;
}

int twice(int a)
{
    return add(a, a);
}

int main()
{
    int i;
    int value;

    i = 1;
    box[i] = twice(box[i - 1]) + add(2, 3);
    value = box[i];
    if (value == 25) {
        return 'Z';
    }
    return 0;
}
