#include <iostream>
#include <string>

using namespace std;

int main() {
    string msg;
    while (true) {
        cin >> msg;
        if (cin.eof())
            break;
        cout << msg + '\n';
    }
    return 0;
}
