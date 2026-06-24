#include <emscripten/bind.h>
#include <emscripten.h>
#include <iostream>
#include <memory>
#include <sstream>
#include <unordered_set>
#include "compiler.h"
#include "image_module.h"
#include "lexer.h"
#include "modules.h"
#include "parser.h"
#include "vm.h"

// VM persists across ollin_run() calls so graphics frame callbacks remain valid.
static std::unique_ptr<VM> s_vm;

static std::string ollin_run(const std::string& source) {
    // Release stale GL texture handles before GL context may be reset.
    image_reset();
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
            Value run_fn = s_vm->getGlobal("graphics").mapGet(Value(std::string("run")));
            if (run_fn.isBuiltin())
                run_fn.asBuiltin()(&draw, 1);
        }
    } catch (const std::exception& e) {
        std::cout.rdbuf(saved);
        return std::string("error: ") + e.what();
    }
    std::cout.rdbuf(saved);
    return out.str();
}

// Preload an image from JS so image.load(name) works on WASM.
// ext: extension without dot, e.g. "png", "jpg"
static void preload_image_js(const std::string& name,
                              const std::string& b64,
                              const std::string& ext) {
    image_preload_b64(name, b64, ext);
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("execute",      &ollin_run);
    emscripten::function("preloadImage", &preload_image_js);
}
