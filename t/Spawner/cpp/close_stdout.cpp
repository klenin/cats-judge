#include <cstdlib>
#include <cstdio>

#ifdef __unix__
#include <unistd.h>
#endif
#ifdef WIN32
#include <windows.h>
#endif

int main(int argc, char** argv) {
    fclose(stdout);

    if (argc > 1) {
        float sleep_time = 0;
        sscanf(argv[1], "%f", &sleep_time);
#ifdef __unix__
        usleep((int)(sleep_time * 1000000));
#endif
#ifdef WIN32
        Sleep((int)(sleep_time * 1000));
#endif
    }
    return 0;
}
