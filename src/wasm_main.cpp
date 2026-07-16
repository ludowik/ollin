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

// Jalon de diagnostic (TEMPORAIRE) : pousse une ligne dans le tampon stderr de
// l'overlay de crash (window.__ollinCrash.noteStderr) → à l'apparition de
// l'overlay, sa section « stderr » montre la DERNIÈRE phase atteinte avant le
// trap. Sert à localiser la phase du re-exécute (relance) qui plante sur iOS.
#define OLLIN_MILE(s) EM_ASM({ if (window.__ollinCrash) window.__ollinCrash.noteStderr("MILE " + UTF8ToString($0)); }, s)

// SONDE (TEMPORAIRE) : reconstruit un module `math` jetable = chemin EXACT du
// crash (makeBuiltinModule("math") → makeMathModule, qui lit des pointeurs de
// fonctions et alloue via les pools/table de chaînes globaux). Posée après
// chaque phase du re-exécute : si la mémoire persistante est empoisonnée, la
// sonde tombe ICI et le dernier jalon « probe<phase> » sans « probeOK<phase> »
// localise la phase fautive. Un trap dur n'est PAS rattrapable (unwind JS) →
// c'est le jalon manquant, pas une exception, qui parle.
static void probe_math(const char* phase) {
    OLLIN_MILE(("probe " + std::string(phase)).c_str());
    {
        Value v = makeBuiltinModule("math");
        (void)v;
    }
    OLLIN_MILE(("probeOK " + std::string(phase)).c_str());
}

static std::string ollin_run(const std::string& source) {
    probe_math("0 entry");
    OLLIN_MILE("A image_reset");
    // Release stale GL texture handles before GL context may be reset.
    image_reset();
    probe_math("A image_reset");
    OLLIN_MILE("B cancel_main_loop");
    // Stop any running graphics loop before destroying the old VM.
    emscripten_cancel_main_loop();
    probe_math("B cancel_main_loop");
    OLLIN_MILE("C destroy old VM");
    s_vm.reset();   // détruire l'ancienne VM AVANT d'en construire une neuve (isole la phase)
    probe_math("C destroy old VM");
    OLLIN_MILE("D new VM");
    s_vm = std::make_unique<VM>();
    probe_math("D new VM");

    std::ostringstream out;
    std::streambuf* saved = std::cout.rdbuf(out.rdbuf());
    try {
        OLLIN_MILE("E parse+compile");
        auto imported = std::make_shared<std::unordered_set<std::string>>();
        Chunk chunk = Compiler().compile(Parser(Lexer(source).tokenize(), "", imported).parse());
        probe_math("E parse+compile");
        OLLIN_MILE("F execute");
        s_vm->execute(std::move(chunk));
        OLLIN_MILE("G runEntryHooks");
        s_vm->runEntryHooks(); // setup() puis draw()→graphics.run (logique partagée, garde isMap)
        OLLIN_MILE("H done");
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
