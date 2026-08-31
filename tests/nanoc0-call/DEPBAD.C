int id(int value)
{
    return value;
}

int main()
{
    return id(id(id(id(id(1)))));
}
