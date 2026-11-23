#include "webcam_module.h"
#include "module_utils.h"
#include "../vm.h"

Value make_webcam_module() {
    auto stub = [](CallCtx& ctx) -> int {
        throw std::runtime_error("webcam: only available in the playground (WASM)");
        return ctx.ret(Value{});
    };
    return MapBuilder()
        .fn("open", stub)
        .fn("capture", stub)
        .fn("close", stub)
        .fn("isOpen", [](CallCtx& ctx) -> int { return ctx.ret(Value::make_bool(false)); })
        .done();
}

void webcam_reset() {}
