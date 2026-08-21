#include "touch_module.h"
#include "value.h"
#include "vm.h"
#include <string>

// Multitouche, build SANS raylib : aucune surface tactile, donc jamais de contact. Le module
// still exists in full, like the sound one: a script reading touch.count() or iterating
// touch.points() then runs and sees nothing, instead of failing on a nil module.

namespace {

int stub_count(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)0));
}

int stub_points(CallCtx& ctx) {
    return ctx.ret(Value::make_array());
}

} // namespace

void touch_begin_frame() {
}

void touch_poll() {
}

void touch_reset() {
}

Value make_touch_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("count")), Value::make_builtin(stub_count));
    m.map_set(Value(std::string("points")), Value::make_builtin(stub_points));
    return m;
}
