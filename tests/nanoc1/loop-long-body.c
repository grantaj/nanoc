/* A bounded byte comparison before a body larger than 128 machine bytes.
 * The loop must branch via a short local skip plus a far JMP to its end.
 * Old direct "bcs exit" would not assemble once the body is this large. */
char i;
char n;
int sum;

int main()
{
    i = 0;
    n = 3;
    sum = 0;
    while (i < n) {
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        sum = sum + 1;
        i = i + 1;
    }
    if (sum == 54) {
        if (i == 3) {
            return 'Z';
        }
    }
    return 0;
}
