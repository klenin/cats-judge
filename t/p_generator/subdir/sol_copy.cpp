#include <fstream>

int main(int argc, char **argv) {
    std::ifstream fin("input.txt");
    int x;
    fin >> x;
    std::ofstream fout("output.txt");
    fout << x;
    return 0;
}
