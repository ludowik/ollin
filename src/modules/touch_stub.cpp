#include "touch_module.h"
#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <string>

// Multitouch, build WITHOUT raylib: no touch surface, hence never a contact. The module
// still exists in full, like the sound one: a script reading touch.count() or iterating
// touch.points() then runs and sees nothing, instead of failing on a nil module. The same
// holds for the callbacks, `pinch` included: they are assigned and simply never called.

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
    return MapBuilder()
        .fn("count", stub_count)
        .fn("points", stub_points)
        .done();
}
