#include "compiler.h"
#include "lexer.h"
#include "modules/camera_module.h"
#include "modules/data_module.h"
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
#include <vector>

// VM persists across ollin_run() calls so graphics frame callbacks remain valid.
static std::unique_ptr<VM> s_vm;

static std::string ollin_run(const std::string& source, const std::string& filename) {
    // Release stale GL texture handles before GL context may be reset.
    image_reset();
    camera_reset();
    // Stop any running graphics loop before destroying the old VM.
    emscripten_cancel_main_loop();
    s_vm = std::make_unique<VM>();

    const std::string fname = filename.empty() ? "<playground>" : filename;
    std::ostringstream out;
    std::streambuf* saved = std::cout.rdbuf(out.rdbuf());
    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        auto source_files = std::make_shared<std::vector<std::string>>();
        source_files->push_back(fname);
        s_vm->execute(Compiler().compile(
            Parser(Lexer(source, fname, 0).tokenize(), "", imported, nullptr, source_files).parse()));
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

// Charge les données persistées (module `data`) avant un run. La SPA lit
// localStorage (portée projet + globale) et passe les deux blobs JSON.
static void data_load_js(const std::string& projectBlob, const std::string& globalBlob) {
    dataLoad(projectBlob, globalBlob);
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("execute", &ollin_run);  // execute(source, filename)
    emscripten::function("preloadImage", &preload_image_js);
    emscripten::function("preloadModel", &preload_model_js);
    emscripten::function("preloadSource", &preload_source_js);
    emscripten::function("resetSources", &source_reset);
    emscripten::function("dataLoad", &data_load_js);
}
