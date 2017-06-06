#include <cstdlib>
#include <iostream>
#include <string>

using namespace std;

#ifdef __unix__
#include <unistd.h>
#endif
#ifdef WIN32
#include <windows.h>
#endif

int main(int argc, char** argv) {
    if (argc < 2)
        return 0;

    int count = atoi(argv[1]);
    int sleep = 200;

    if (argc > 2) {
        sleep = atoi(argv[2]);
    }

    for (int i = 1; i <= count; i++) {
        cout << i << "W#" << endl;
    }

#ifdef __unix__
            usleep(sleep * 000);
#endif
#ifdef WIN32
            Sleep(sleep);
#endif

    return 0;
}
