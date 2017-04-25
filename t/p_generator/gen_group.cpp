#include <fstream>

int main(int argc, char **argv) {
    for (int i = 4; i <= 6; ++i) {
        char name[] = "0.in";
        name[0] += i;
        std::ofstream f(name);
        f << i;
    }
    return 0;
}
