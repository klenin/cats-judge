#include <iostream>
#include <string>

using namespace std;
int main() {
    const string data = "111111111";
    string msg;
    for (int i = 0; i < 5000; i++) {
        cout << data + '\n';
        cin >> msg;
        if (msg != data)
            return 1;
    }
    return 0;
}
