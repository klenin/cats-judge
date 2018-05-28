#include <fstream>

int main(int argc, char **argv) {
    std::ofstream f("input.txt");
    f << argv[1];
    return 0;
}
