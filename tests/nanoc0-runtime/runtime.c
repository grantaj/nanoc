int read_handle;
int write_handle;

int test_mul()
{
    unsigned value;

    value = 65535;
    if (value * 2 != 65534) {
        return 1;
    }
    return 0;
}

int test_open()
{
    read_handle = io_open("RUNTIME.IN", 10);
    if (read_handle < 0) {
        return 1;
    }
    return 0;
}

int test_open_missing()
{
    if (io_open("MISSING", 7) != -1) {
        return 1;
    }
    return 0;
}

int test_read()
{
    int value;

    value = io_read(read_handle);
    if (value != 'A') {
        return 1;
    }
    return 0;
}

int test_read_bad_handle()
{
    if (io_read(99) != -2) {
        return 1;
    }
    return 0;
}

int test_close_read()
{
    if (io_close(read_handle) != 0) {
        return 1;
    }
    return 0;
}

int test_create()
{
    write_handle = io_create("DTEST", 5);
    if (write_handle < 0) {
        return 1;
    }
    return 0;
}

int test_write()
{
    if (io_write(write_handle, 'Z') != 0) {
        return 1;
    }
    return 0;
}

int test_close_write()
{
    if (io_close(write_handle) != 0) {
        return 1;
    }
    return 0;
}

int main()
{
    int handle;
    int value;
    int index;
    char *text;
    unsigned u;

    handle = io_open("RUNTIME.IN", 10);
    if (handle < 0) {
        return 1;
    }
    value = io_read(handle);
    if (value != 'A') {
        return 2;
    }
    value = io_read(handle);
    if (value != 'B') {
        return 3;
    }
    value = io_read(handle);
    if (value != 'C') {
        return 4;
    }
    value = io_read(handle);
    if (value != -1) {
        return 5;
    }
    if (io_close(handle) != 0) {
        return 6;
    }

    if (io_open("MISSING", 7) != -1) {
        return 7;
    }

    u = 0;
    if (u * 4660 != 0) {
        return 8;
    }
    u = 1;
    if (u * 65535 != 65535) {
        return 9;
    }
    u = 65535;
    if (u * 2 != 65534) {
        return 10;
    }

    handle = io_create("SMOKE.ASM", 9);
    if (handle < 0) {
        return 11;
    }

    text = "* = $2000";
    index = 0;
    while (index < 9) {
        if (io_write(handle, text[index]) != 0) {
            return 12;
        }
        index = index + 1;
    }
    if (io_write(handle, 10) != 0) {
        return 13;
    }

    text = "byte $2a";
    index = 0;
    while (index < 8) {
        if (io_write(handle, text[index]) != 0) {
            return 14;
        }
        index = index + 1;
    }
    if (io_write(handle, 10) != 0) {
        return 15;
    }
    if (io_close(handle) != 0) {
        return 16;
    }

    return 0;
}
