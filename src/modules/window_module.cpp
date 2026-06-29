#include "value.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/val.h>

Value makeWindowModule() {
    // Zone de dessin disponible : le conteneur #output-pane du playground s'il
    // existe, sinon le viewport (page autonome run.html, page externe…).
    // Sans repli, getElementById renvoie null → null.clientWidth plante.
    auto document = emscripten::val::global("document");
    auto pane = document.call<emscripten::val>("getElementById", std::string("output-pane"));
    int w, h;
    if (pane.isNull() || pane.isUndefined()) {
        auto win = emscripten::val::global("window");
        w = win["innerWidth"].as<int>();
        h = win["innerHeight"].as<int>();
    } else {
        w = pane["clientWidth"].as<int>();
        h = pane["clientHeight"].as<int>();
    }
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("width")),  Value((int64_t)w));
    m.mapSet(Value(std::string("height")), Value((int64_t)h));
    return m;
}

#elif defined(OLLIN_HAS_RAYLIB)

Value makeWindowModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("width")),  Value((int64_t)800));
    m.mapSet(Value(std::string("height")), Value((int64_t)600));
    return m;
}

#else

Value makeWindowModule() { return Value(); }

#endif
