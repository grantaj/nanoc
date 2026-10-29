/* Same byte-bound loop shape as bootstrap/ass.c's same_text. */
char lhs[5] = {'a', 'b', 'c', 'd', 'e'};
char rhs[5] = {'a', 'b', 'c', 'd', 'e'};

int equals(char *a, char *b, char length)
{
    char j = 0;

    while (j < length) {
        if (a[j] != b[j]) {
            return 0;
        }
        j = j + 1;
    }
    return 1;
}

int main()
{
    if (equals(lhs, rhs, 5) != 1) {
        return 1;
    }
    rhs[3] = 'x';
    if (equals(lhs, rhs, 5) != 0) {
        return 2;
    }
    return 'Z';
}
