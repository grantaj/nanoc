/* Pointer values are passed as ordinary two-byte Phase-1 arguments.
 * The actual indexed dereference occurs in the callee. */
char first_pointed(char *data)
{
    return data[0];
}

char forwarding_pointer(char *data)
{
    return first_pointed(data);
}

char selected_pointed(char *data, char offset)
{
    return data[offset];
}

char forwarding_pointer_index(char *data, char offset)
{
    return selected_pointed(data,offset);
}
