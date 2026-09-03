#include "compiler.h"
#include "lexer.h"
#include "modules/audio_module.h"
#include "modules/sound_module.h"
#include "modules/touch_module.h"
#include "modules/mouse_module.h"
#include "modules/camera_module.h"
#include "modules/engine_font.h"
#include "modules/ui_module.h"
#include "modules/tween_module.h"
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
    ui_reset();   // the previous program's widgets: the statics outlive the VM
    tween_reset();   // likewise: a surviving tween would retain the previous program's objects
    audio_reset();   // the master volume, which a previous program may have turned down
    sound_reset();   // otherwise an oscillator of the previous program would keep sounding
    touch_reset();   // a finger left "down" would look like a gesture under way
    mouse_reset();   // nor a button left pressed
    engine_font_reset();   // the atlases belonged to the previous GL context
    // Stop any running graphics loop before destroying the old VM.
    emscripten_cancel_main_loop();
    s_vm = std::make_unique<VM>();

    const std::string fname = filename.empty() ? "<playground>" : filename;
    // An import resolves relative to the DIRECTORY of the importing file, and the entry file is no
    // exception: hard-coding an empty base directory meant an entry kept in a sub-directory looked
    // for its siblings at the root instead — it ran natively and not on the web. path_dir is the
    // single place that rule lives now.
    const std::string base_dir = path_dir(fname);
    program_dir_set(base_dir);   // the resources a script names are looked for beside it
    std::ostringstream out;
    std::streambuf* saved = std::cout.rdbuf(out.rdbuf());
    try {
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        auto source_files = std::make_shared<std::vector<std::string>>();
        source_files->push_back(fname);
        s_vm->execute(Compiler().compile(
            Parser(Lexer(source, fname, 0).tokenize(), base_dir, imported, nullptr, source_files).parse()));
        s_vm->run_entry_hooks(); // setup(), then draw() through graphics.run: shared logic, with the is_map guard
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

// Loads persisted `data` before a run: the SPA reads localStorage (project and global scopes)
// and passes both JSON blobs.
static void data_load_js(const std::string& project_blob, const std::string& global_blob) {
    data_load(project_blob, global_blob);
}

// Screenshot requested by the HOST (the fullscreen button). It takes two steps because a
// capture is only possible at the end of a frame: request_capture records the request, and
// take_capture returns the PNG as base64 once a frame has produced it (empty string until
// then).
static void request_capture_js() {
    gfx_request_capture();
}

static std::string take_capture_js() {
    return gfx_take_capture();
}

// The host declares that it stopped the loop (the Pause button, and the capture, which resumes it
// for a single frame): the interval spent stopped must not be credited to the program.
static void clock_break_js() {
    gfx_clock_break();
}

EMSCRIPTEN_BINDINGS(ollin) {
    emscripten::function("execute", &ollin_run);  // execute(source, filename)
    emscripten::function("preloadImage", &preload_image_js);
    emscripten::function("preloadModel", &preload_model_js);
    emscripten::function("preloadSource", &preload_source_js);
    emscripten::function("resetSources", &source_reset);
    emscripten::function("dataLoad", &data_load_js);
    emscripten::function("requestCapture", &request_capture_js);
    emscripten::function("takeCapture", &take_capture_js);
    emscripten::function("clockBreak", &clock_break_js);
}
