#pragma once
#include "chunk.h"
#include <stack>
#include <string>
#include <unordered_map>

class VM {
public:
    void execute(const Chunk& chunk);

private:
    std::stack<double> stack;
    std::unordered_map<std::string, double> vars;
};
