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
    int mode = -1;
    string msg = "";
    for (int i = 1; i < argc; i++) {
        mode = atoi(argv[i]);
        switch(mode) {
            case 0:
                cout << "1W#" << endl;
                break;
            case 1:
                cout << "1S#" << endl;
                break;
            case 2:
                cout << "1#msg" << endl;
                break;
            case 3:
                cin >> msg;
                break;
            case 4:
                cout << "0#" << msg << endl;
                break;
            case 5:
                cerr << msg << endl;
                break;
            case 6:
                cout << "999#msg" << endl;
            case 7:
#ifdef __unix__
                usleep(200000);
#endif
#ifdef WIN32
                Sleep(200);
#endif
                break;
            default:
                return -1;
        }
    }
    return mode;
}
