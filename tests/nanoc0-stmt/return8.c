char byte_return_sub(char value)
{
    return value - 32;
}

char byte_assignment_add(char value)
{
    char result;
    result = value + 10;
    return result;
}

char byte_assignment_mul3(char value)
{
    char result;
    result = value * 3;
    return result;
}

int word_mul3(char value)
{
    return value * 3;
}

char nested_word_mul3(char value)
{
    return (value * 3) >> 8;
}

int main()
{
    char value;

    value = 200;
    if (byte_return_sub('a') != 'A') {
        return 1;
    }
    if (byte_assignment_add(value) != 210) {
        return 2;
    }
    if (byte_assignment_mul3(value) != 88) {
        return 3;
    }
    if (word_mul3(value) != 600) {
        return 4;
    }
    if (nested_word_mul3(value) != 2) {
        return 5;
    }

    return 'Z';
}
