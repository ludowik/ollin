#include <emscripten/bind.h>
#include <emscripten.h>
#include <iostream>
#include <memory>
#include <sstream>
#include <unordered_set>
#include "compiler.h"
#include "lexer.h"
#include "parser.h"
#include "vm.h"

// VM persists across ollin_run() calls so graphics frame callbacks remain valid.
static std::unique_ptr<VM> s_vm;

static std::string ollin_run(const std::string& source) {
    // Stop any running graphics loop before destroying the old VM.
    emscripten_cancel_main_loop();
    s_vm = std::make_unique<VM>();

    std::ostringstream out;
    std::streambuf* saved = std::cout.rdbuf(out.rdbuf());
    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        s_vm->execute(Compiler().compile(
            Parser(Lexer(source).tokenize(), "", imported).parse()
        ));
        Value draw = s_vm->getGlobal("draw");
        if (draw.isCallable()) {
            Value gfx = s_vm->getGlobal("graphics");
            if (gfx.isMap()) {
                Value run_fn = gfx.mapGet(Value(std::string("run")));
                if (run_fn.isCallable()) {
                    Value args[1] = { draw };
                    run_fn.asBuiltin()(args, 1);
                }
            }
        }
    } catch (const std::exception& e) {
        std::cout.rdbuf(saved);
        return std::string("error: ") + e.what();
    }
    std::cout.rdbuf(saved);
    return out.str();
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("execute", &ollin_run);
}
