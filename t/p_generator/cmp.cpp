#include <fstream>

int main(int argc, char **argv) {
    std::ifstream fin(argv[1]);
    std::ifstream fout(argv[2]);
    std::ifstream fans(argv[3]);
    int xin, xout, xans;
    fin >> xin;
    fout >> xout;
    fans >> xans;
    if (xans != xin) return 3;
    if (xout != xin) return 1;
    return 0;
}
