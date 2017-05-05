#include <iostream>
#include <fstream>

int main() {
    std::ifstream fin("input.txt");
    std::ofstream fout("output.txt");
    while(fin && !fin.eof()) {
        int x;
        fin >> x;
        std::cout << x << std::endl;
        std::cout.flush();
        int y;
        std::cin >> y;
        if (x == y) continue;
        fout << 1 << std::endl;
        return 0;
    }
    std::cout << 0 << std::endl;
    std::cout.flush();
    fout << 0 << std::endl;
    return 0;
}
