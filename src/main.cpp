#include "compiler.h"
#include "lexer.h"
#include "parser.h"
#include "vm.h"
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_set>

static Program parseFile(const std::string& path) {
    std::ifstream f(path);
    if (!f)
        return {};
    std::ostringstream ss;
    ss << f.rdbuf();
    return Parser(Lexer(ss.str()).tokenize()).parse();
}

static void appendProgram(Program& dst, Program src) {
    for (auto& s : src.stmts)
        dst.stmts.push_back(std::move(s));
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: ollin <file.ol>\n";
        return 1;
    }

    std::string scriptPath(argv[1]);
    auto sep = scriptPath.find_last_of("/\\");
    std::string dir = (sep != std::string::npos) ? scriptPath.substr(0, sep + 1) : "";

    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        Program program;
        appendProgram(program, parseFile(dir + "config.ol"));

        std::ifstream main_file(scriptPath);
        if (!main_file) {
            std::cerr << "cannot open: " << scriptPath << '\n';
            return 1;
        }
        std::ostringstream ss;
        ss << main_file.rdbuf();
        appendProgram(program, Parser(Lexer(ss.str()).tokenize(), dir, imported).parse());

        VM vm;
        vm.execute(Compiler().compile(program));
        // setup() : appelée une fois après le chargement, avant la boucle update/draw
        Value setup = vm.getGlobal("setup");
        if (setup.isCallable())
            vm.callValue(setup);
        Value draw = vm.getGlobal("draw");
        if (draw.isCallable()) {
            Value gfx = vm.getGlobal("graphics");
            if (gfx.isMap()) {
                Value run_fn = gfx.mapGet(Value(std::string("run")));
                if (run_fn.isBuiltin())
                    run_fn.asBuiltin()(&draw, 1);
            }
        }
    } catch (const std::exception& e) {
        std::cerr << scriptPath << ": " << e.what() << '\n';
        return 1;
    }
    return 0;
}
