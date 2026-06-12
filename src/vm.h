#pragma once
#include "chunk.h"
#include <stack>
#include <vector>

class VM {
public:
    void execute(const Chunk& chunk);

private:
    struct Handler {
        uint16_t catch_addr;
        size_t   stack_size;
    };

    std::stack<Value, std::vector<Value>> stack;
    std::vector<Value>   vars;
    std::vector<bool>    vars_init;
    std::vector<Handler> handler_stack;
};
