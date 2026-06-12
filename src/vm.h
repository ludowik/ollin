#pragma once
#include "chunk.h"
#include <stack>
#include <string>
#include <unordered_map>

class VM {
public:
    void execute(const Chunk& chunk);

private:
    std::stack<Value>                    stack;
    std::unordered_map<std::string, Value> vars;
};
