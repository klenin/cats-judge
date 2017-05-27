#include <iostream>

int main() {
    for (int i = 0; ; ++i) {
        std::cout << "0";
        if (i % 1000 == 0)
            std::cout.flush();
    }
    return 0;
}
