#include "module_utils.h"
#include "value.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/val.h>

Value make_window_module() {
    // Available drawing area: the playground's #output-pane container when it
    // exists, otherwise the viewport (the standalone run.html, an external page).
    // Without a fallback, getElementById returns null and null.clientWidth throws.
    auto win = emscripten::val::global("window");
    int w = 0, h = 0;
    // 1) Size PROVIDED by the host. In the playground it is the render area measured in JS after
    // layout, which is reliable — unlike reading the DOM at init, where a layout race is possible.
    auto ow = win["__ollinRenderW"];
    auto oh = win["__ollinRenderH"];
    if (ow.isNumber() && oh.isNumber()) {
        w = ow.as<int>();
        h = oh.as<int>();
    }
    // 2) Otherwise #output-pane is read directly (run.html, an external page).
    if (w <= 0 || h <= 0) {
        auto document = emscripten::val::global("document");
        auto pane = document.call<emscripten::val>("getElementById", std::string("output-pane"));
        if (!pane.isNull() && !pane.isUndefined()) {
            w = pane["clientWidth"].as<int>();
            h = pane["clientHeight"].as<int>();
        }
    }
    // 3) Last resort, the viewport, so W and H always hold a REAL size and never 0.
    // (otherwise the canvas would be empty, with no GL context, and crash).
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
    return MapBuilder()
        .int_num("width", 800)
        .int_num("height", 600)
        .done();
}

#else

Value make_window_module() {
    return Value();
}

#endif
