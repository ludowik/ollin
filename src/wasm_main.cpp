#include "compiler.h"
#include "lexer.h"
#include "modules/graphics_internal.h"
#include "modules/image_module.h"
#include "modules/modules.h"
#include "parser.h"
#include "source_registry.h"
#include "vm.h"
#include <emscripten.h>
#include <emscripten/bind.h>
#include <iostream>
#include <memory>
#include <sstream>
#include <unordered_set>

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
        s_vm->execute(Compiler().compile(Parser(Lexer(source).tokenize(), "", imported).parse()));
        s_vm->runEntryHooks(); // setup() puis draw()→graphics.run (logique partagée, garde isMap)
    } catch (const std::exception& e) {
        std::cout.rdbuf(saved);
        return std::string("error: ") + e.what();
    }
    std::cout.rdbuf(saved);
    return out.str();
}

// Preload an image from JS so image.load(name) works on WASM.
// ext: extension without dot, e.g. "png", "jpg"
static void preload_image_js(const std::string& name, const std::string& b64, const std::string& ext) {
    image_preload_b64(name, b64, ext);
}

// Preload a 3D model from JS so graphics.model(name) works on WASM.
// ext: extension without dot, e.g. "obj", "glb".
static void preload_model_js(const std::string& name, const std::string& b64, const std::string& ext) {
    model_preload_bytes(name, image_b64_decode(b64), std::string(".") + ext);
}

// Preload a .ol source file from JS so `import "path"` resolves against it
// (used to run multi-file projects in the playground). Key = project-relative
// path, e.g. "utils.ol" or "lib/helper.ol".
static void preload_source_js(const std::string& path, const std::string& content) {
    source_preload(path, content);
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("execute", &ollin_run);
    emscripten::function("preloadImage", &preload_image_js);
    emscripten::function("preloadModel", &preload_model_js);
    emscripten::function("preloadSource", &preload_source_js);
    emscripten::function("resetSources", &source_reset);
}
