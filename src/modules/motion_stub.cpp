#include "motion_module.h"
#include "module_utils.h"
#include "value.h"
#include "vm.h"

// The motion sensors, build WITHOUT raylib: there is no sensor, hence the state is "unsupported" as
// soon as the script asks. The module still exists in full, like touch and sound: a script reading
// motion.tilt() runs and sees zeros instead of failing on a nil module.

namespace {

bool s_wanted = false;

int stub_state(CallCtx& ctx) {
    return ctx.ret(Value(std::string(s_wanted ? "unsupported" : "off")));
}

int stub_enable(CallCtx& ctx) {
    s_wanted = true;
    return stub_state(ctx);
}

int stub_pair(CallCtx& ctx) {
    ctx.set_result(0, Value(0.0));
    ctx.set_result(1, Value(0.0));
    return 2;
}

int stub_triple(CallCtx& ctx) {
    ctx.set_result(0, Value(0.0));
    ctx.set_result(1, Value(0.0));
    ctx.set_result(2, Value(0.0));
    return 3;
}

int stub_attitude(CallCtx& ctx) {
    return ctx.ret(Value{});
}

} // namespace

void motion_begin_frame() {
}

void motion_reset() {
    s_wanted = false;
}

Value make_motion_module() {
    return MapBuilder()
        .fn("enable", stub_enable)
        .fn("state", stub_state)
        .fn("tilt", stub_pair)
        .fn("gravity", stub_triple)
        .fn("acceleration", stub_triple)
        .fn("attitude", stub_attitude)
        .done();
}
