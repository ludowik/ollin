#include "value.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/val.h>

Value makeWindowModule() {
    auto document = emscripten::val::global("document");
    auto pane = document.call<emscripten::val>("getElementById", std::string("output-pane"));
    int w = pane["clientWidth"].as<int>();
    int h = pane["clientHeight"].as<int>();
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("width")), Value((int64_t)w));
    m.mapSet(Value(std::string("height")), Value((int64_t)h));
    return m;
}

#elif defined(OLLIN_HAS_RAYLIB)

Value makeWindowModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("width")), Value((int64_t)800));
    m.mapSet(Value(std::string("height")), Value((int64_t)600));
    return m;
}

#else

Value makeWindowModule() {
    return Value();
}

#endif
