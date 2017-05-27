#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using namespace std;

int main(int argc, char** argv) {
    string msg;
    vector<int> agents;

    for (int i = 1; i < argc; i++) {
        agents.push_back(atoi(argv[i]));
    }

    for (int i = 0; i < agents.size(); i++) {
        int agent = agents[i];
        string status = "";
        char buffer[10];
        sprintf(buffer, "%d", agent);
        string agent_str = buffer;
        string err_message = "";
        cout << agent << "W#" << endl;
        cout.flush();
        cout << agent << "#some_message" << endl;
        cout.flush();

        while (!cin.eof()) {
            msg = "";
            cin >> msg;
            cout << "0# " << msg << endl;
            cout.flush();
            if (msg == agent_str + "T#") {
                if (status.empty())
                    status = "TERMINATED";
                cerr << agent << status << err_message << endl;
                break;
            }
            if (msg == agent_str + "#some_message") {
                status = "OK";
            } else {
                status = "FAIL";
                err_message = msg.empty() ? " empty message (or cin eof)" : (" wrong answer: " + msg);
            }

            cout << agent << "S#" << endl;
            cout.flush();
        }
    }

    return 0;
}
