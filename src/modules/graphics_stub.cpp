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
