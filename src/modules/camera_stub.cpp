#include "camera_module.h"

Value makeCameraModule() {
    Value m = Value::makeMap();
    auto stub = [](CallCtx& ctx) -> int {
        throw std::runtime_error("camera: non disponible en dehors du playground (WASM)");
        return ctx.ret(Value{});
    };
    m.mapSet(Value(std::string("open")),    Value::makeBuiltin(stub));
    m.mapSet(Value(std::string("capture")), Value::makeBuiltin(stub));
    m.mapSet(Value(std::string("close")),   Value::makeBuiltin(stub));
    m.mapSet(Value(std::string("isOpen")),  Value::makeBuiltin([](CallCtx& ctx) -> int { return ctx.ret(Value(int64_t(0))); }));
    return m;
}
