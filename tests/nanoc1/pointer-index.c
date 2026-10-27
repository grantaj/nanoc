int main()
{
    char *p = "WXYZ";
    char *text = "ABC";
    if ("ABC"[1] != 'B') {
        return 1;
    }
    if (p[1] != 'X') {
        return 2;
    }
    if ((p + 1)[2] != 'Z') {
        return 3;
    }
    if ((text + 1)[1] != 'C') {
        return 4;
    }
    return 'Z';
}
