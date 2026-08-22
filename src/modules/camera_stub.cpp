#include "camera_module.h"

Value make_camera_module() {
    Value m = Value::make_map();
    auto stub = [](CallCtx& ctx) -> int {
        throw std::runtime_error("camera: only available in the playground (WASM)");
        return ctx.ret(Value{});
    };
    m.map_set(Value(std::string("open")),    Value::make_builtin(stub));
    m.map_set(Value(std::string("capture")), Value::make_builtin(stub));
    m.map_set(Value(std::string("close")),   Value::make_builtin(stub));
    m.map_set(Value(std::string("isOpen")),  Value::make_builtin([](CallCtx& ctx) -> int { return ctx.ret(Value::make_bool(false)); }));
    return m;
}
