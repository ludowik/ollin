#include "touch_module.h"
#include "value.h"
#include "vm.h"
#include <string>

// Multitouche, build SANS raylib : aucune surface tactile, donc jamais de contact. Le module
// existe tout de même en entier, comme celui du son — un script qui lit `touch.count()` ou
// itère `touch.points()` tourne alors sans rien voir, au lieu d'échouer sur un module nil.

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
