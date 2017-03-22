#include <cstdio>
#include <fstream>
#include <iostream>

using namespace std;

int main(int argc, char** argv)
{
    if (argc > 2) {
        cerr << argv[2];
    }
    if (argc > 1) {
        cout << argv[1];
        return 0;
    }
    int ch;
    while (true) {
        ch = getchar();
        if (ch == EOF)
            break;
        putchar(ch);
        fflush(stdout);
    }
    return 0;
}
