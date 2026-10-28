char a[5] = {7, 9, 11, 13, 15};
char b[5] = {1, 2, 3, 4, 5};
char index = 1;

char move_index()
{
    index = 3;
    return 0;
}

int main()
{
    char x = 0;
    char y = 0;
    char z = 0;

    /* Three independent expressions should load index into Y only once. */
    x = a[index];
    y = b[index];
    z = a[index];
    if (x != 9) {
        return 1;
    }
    if (y != 2) {
        return 2;
    }
    if (z != 9) {
        return 3;
    }

    /* Branch join and direct assignment invalidate the cached identity. */
    if (x == 9) {
        index = 2;
    } else {
        index = 4;
    }
    x = a[index];
    y = b[index];
    if (x != 11) {
        return 4;
    }
    if (y != 3) {
        return 5;
    }

    /* Function calls can change the global source even if A/X survives. */
    move_index();
    z = a[index];
    if (z != 13) {
        return 6;
    }
    return 'Z';
}
