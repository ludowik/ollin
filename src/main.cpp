#include "lexer.h"
#include "parser.h"
#include "compiler.h"
#include "vm.h"
#include <fstream>
#include <iostream>
#include <sstream>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: tau <file.tau>\n";
        return 1;
    }
    std::ifstream file(argv[1]);
    if (!file) {
        std::cerr << "cannot open: " << argv[1] << '\n';
        return 1;
    }
    std::ostringstream ss;
    ss << file.rdbuf();

    try {
        auto tokens  = Lexer(ss.str()).tokenize();
        auto program = Parser(std::move(tokens)).parse();
        auto chunk   = Compiler().compile(program);
        VM().execute(chunk);
    } catch (const std::exception& e) {
        std::cerr << argv[1] << ": " << e.what() << '\n';
        return 1;
    }
    return 0;
}
