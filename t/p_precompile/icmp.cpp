#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
    std::ifstream fout(argv[2]);
    int o = 0;
    fout >> o;
    std::ifstream fans(argv[3]);
    int a = 0;
    fans >> a;
    return o != a;
}
