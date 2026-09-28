char byte_slot[1];

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

char byte_initializer_mul3(char value)
{
    char result = value * 3;
    return result;
}

char take_byte(char value)
{
    return value;
}

int take_word(int value)
{
    return value;
}

char byte_argument_mul3(char value)
{
    return take_byte(value * 3);
}

int word_argument_mul3(char value)
{
    return take_word(value * 3);
}

char byte_argument_nested_word(char value)
{
    return take_byte((value * 3) >> 8);
}

char byte_shift8(int value)
{
    return value >> 8;
}

int word_shift8(int value)
{
    return value >> 8;
}

char byte_indexed_mul3(char value)
{
    byte_slot[0] = value * 3;
    return byte_slot[0];
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
    if (byte_initializer_mul3(value) != 88) {
        return 6;
    }
    if (byte_argument_mul3(value) != 88) {
        return 7;
    }
    if (word_argument_mul3(value) != 600) {
        return 8;
    }
    if (byte_argument_nested_word(value) != 2) {
        return 9;
    }
    if (byte_shift8(4660) != 18) {
        return 10;
    }
    if (word_shift8(4660) != 18) {
        return 11;
    }
    if (byte_indexed_mul3(value) != 88) {
        return 12;
    }

    return 'Z';
}
