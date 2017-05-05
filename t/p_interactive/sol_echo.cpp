#include <iostream>

int main() {
    while (1) {
        int x;
        std::cin >> x;
        if (!x) break;
        std::cout << x << std::endl;
        std::cout.flush();
    }
    return 0;
}
