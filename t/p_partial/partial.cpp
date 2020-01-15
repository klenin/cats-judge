#include <iostream>
#include <fstream>

int main(int argc, char** argv) {
    std::ifstream fout(argv[2]);
    int x = 0;
    fout >> x;
    if (x == 1) { std::cout << "5"; return 0; }
    else { return 0; }
}
