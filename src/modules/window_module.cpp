#include "value.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/val.h>

Value make_window_module() {
    // Zone de dessin disponible : le conteneur #output-pane du playground s'il
    // existe, sinon le viewport (page autonome run.html, page externe…).
    // Sans repli, getElementById renvoie null → null.clientWidth plante.
    auto win = emscripten::val::global("window");
    int w = 0, h = 0;
    // 1) Taille FOURNIE par l'hôte (playground : zone de rendu mesurée en JS après
    // affichage — fiable, pas de course de layout comme la lecture DOM à l'init).
    auto ow = win["__ollinRenderW"];
    auto oh = win["__ollinRenderH"];
    if (ow.isNumber() && oh.isNumber()) {
        w = ow.as<int>();
        h = oh.as<int>();
    }
    // 2) Sinon lecture directe de #output-pane (run.html, page externe…).
    if (w <= 0 || h <= 0) {
        auto document = emscripten::val::global("document");
        auto pane = document.call<emscripten::val>("getElementById", std::string("output-pane"));
        if (!pane.isNull() && !pane.isUndefined()) {
            w = pane["clientWidth"].as<int>();
            h = pane["clientHeight"].as<int>();
        }
    }
    // 3) Dernier repli : viewport → W/H toujours une taille RÉELLE, jamais 0
    // (sinon canvas à vide, sans contexte GL → crash).
    if (w <= 0 || h <= 0) {
        w = win["innerWidth"].as<int>();
        h = win["innerHeight"].as<int>();
    }
    Value m = Value::make_map();
    m.map_set(Value(std::string("width")), Value((int64_t)w));
    m.map_set(Value(std::string("height")), Value((int64_t)h));
    return m;
}

#elif defined(OLLIN_HAS_RAYLIB)

Value make_window_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("width")), Value((int64_t)800));
    m.map_set(Value(std::string("height")), Value((int64_t)600));
    return m;
}

#else

Value make_window_module() {
    return Value();
}

#endif
