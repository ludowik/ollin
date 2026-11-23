#include "value.h"

Value make_graphics_module() {
    return Value();
}
Value make_keyboard_module() {
    return Value();
}
Value make_mouse_module() {
    return Value();
}
Value make_blend_module() {
    return Value();
}
// Nothing to forget without a window, a mouse or a button: the module table (modules.cpp) names these in every build.
void gfx_program_reset() {}
void mouse_reset() {}
// The 3D classes exist only with a window: the registry of native classes (modules.cpp) skips a nil.
Value camera_class() {
    return Value();
}
Value light_class() {
    return Value();
}
Value quat_class() {
    return Value();
}
