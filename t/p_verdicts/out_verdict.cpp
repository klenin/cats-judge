#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char** argv) {
    std::ifstream fout(argv[2]);
    int x = 0;
    fout >> x;
    return x;
}
