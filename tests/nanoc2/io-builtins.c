/* Phase-1 native I/O ABI contract: all five builtins are ordinary calls.
 * The rejected inputs avoid depending on an attached C64 drive.
 */
char io_name[8];

int reject_open()
{
    return io_open(io_name, 256);
}

int reject_create()
{
    return io_create(io_name, 256);
}

int reject_read()
{
    return io_read(6);
}

int reject_write()
{
    return io_write(6, 65);
}

int reject_close()
{
    return io_close(6);
}
