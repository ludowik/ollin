#pragma once
#include "chunk.h"
#include <stack>
#include <string>
#include <unordered_map>
#include <vector>

class VM {
public:
    void execute(const Chunk& chunk);

private:
    struct Handler {
        uint16_t catch_addr;
        size_t   stack_size;
    };

    std::stack<Value>                    stack;
    std::unordered_map<std::string, Value> vars;
    std::vector<Handler>                 handler_stack;
};
