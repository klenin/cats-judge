#include <string>
#include <cstdio>

int main(int argc, char* argv[]) {
    if (argc != 2)
        return 0;
    FILE* f = fopen(argv[1], "r");
    int ch, fch;
    while (ch != EOF || fch != EOF) {
        ch = getchar();
        fch = getc(f);
        if (ch != EOF) {
            putchar(ch);
            fflush(stdout);
        }
        if (fch != EOF) {
            putchar(ch);
            fflush(stdout);
        }
    }

    fclose(f);

    return 0;
}
