#include <emscripten/bind.h>
#include <iostream>
#include <memory>
#include <sstream>
#include <unordered_set>
#include "compiler.h"
#include "lexer.h"
#include "parser.h"
#include "vm.h"

static std::string ollin_run(const std::string& source) {
    std::ostringstream out;
    std::streambuf* saved = std::cout.rdbuf(out.rdbuf());
    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        VM().execute(Compiler().compile(
            Parser(Lexer(source).tokenize(), "", imported).parse()
        ));
    } catch (const std::exception& e) {
        std::cout.rdbuf(saved);
        return std::string("error: ") + e.what();
    }
    std::cout.rdbuf(saved);
    return out.str();
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("run", &ollin_run);
}
