#include <cstdlib>

int main() {
    int n = 100;
    int size = 1024 * 1024;
    char** a = new char*[n];
    for (int j = 0; j < n; j++) {
        a[j] = new char[size];
        for (int i = 0; i < size; i++) {
            a[j][i] = rand() % 256;
        }
    }

    for (int j = 0; j < n; j++) {
        delete a[j];
    }

    delete a;
}
