#include "mouse_module.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <string>
#include <cmath>

// Functions are assigned to the `mouse` module and the engine calls whichever
// exist, with no activation needed, passing the position (x, y) in the logical
// the graphics area's logical coordinates:
//   mouse.pressed  = func(x, y) ... end   left button pressed
//   mouse.released = func(x, y) ... end   released
//   mouse.moved    = func(x, y) ... end   pointer moved
//
// Detection happens in mouse_poll(), called once per frame by the render loop
// loop (graphics_module.cpp), so the pointer only works during a
// graphics.run(...) — or through the automatically called draw function.

static float s_last_click_time = -1.0f;
static int   s_last_click_x    = -9999;
static int   s_last_click_y    = -9999;
static const float DBLCLICK_DELAY = 0.30f;
static const int   DBLCLICK_DIST  = 8;
// The script received a `pressed` with no `released` yet: an invariant to hold, whatever happens.
static bool s_down = false;

void mouse_poll(bool click_taken) {
    VM* vm = VM::current();
    Value m = vm->get_global("mouse");
    if (!m.is_map())
        return;
    Value pressed       = m.map_get(Value(std::string("pressed")));
    Value released      = m.map_get(Value(std::string("released")));
    Value moved         = m.map_get(Value(std::string("moved")));
    Value scrolled      = m.map_get(Value(std::string("scrolled")));
    Value double_clicked = m.map_get(Value(std::string("doubleClicked")));

    int mx = GetMouseX();
    int my = GetMouseY();
    Value x = Value((int64_t)mx);
    Value y = Value((int64_t)my);

    // The click was taken by a UI widget, so the script must not see the release either —
    // otherwise an interface button would also fire mouse.released.
    if (click_taken)
        pressed = released = double_clicked = Value{};
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        float now = GetTime();
        bool dbl = double_clicked.is_callable()
            && (now - s_last_click_time) < DBLCLICK_DELAY
            && std::abs(mx - s_last_click_x) < DBLCLICK_DIST
            && std::abs(my - s_last_click_y) < DBLCLICK_DIST;
        if (dbl) {
            vm->call_value(double_clicked, x, y);
            s_last_click_time = -1.0f;   // reset, so a triple click does not fire it
        } else {
            if (pressed.is_callable())
                vm->call_value(pressed, x, y);
            s_last_click_time = now;
            s_last_click_x    = mx;
            s_last_click_y    = my;
        }
        // A click taken by a widget does not belong to the script, which must not receive its
        // release either — both callbacks are already cleared above.
        s_down = !click_taken;
    }
    // The release is derived from the button's STATE, not from the IsMouseButtonReleased event:
    // that event NEVER arrives when mouse emulation stops mid-press, which is what the browser
    // does as soon as a second finger lands (rcore_web.c only copies the position
    // `if (pointCount == 1)`). A press was then left without its release, and any script holding
    // a "button down" state — drag and drop, freehand drawing, a held note — kept it forever.
    // Reading the state also covers focus loss and any other missed event, without having to
    // enumerate the causes.
    if (s_down && !IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
        s_down = false;
        if (released.is_callable())
            vm->call_value(released, x, y);
    }
    if (moved.is_callable()) {
        Vector2 d = GetMouseDelta();
        if (d.x != 0.0f || d.y != 0.0f)
            vm->call_value(moved, x, y);
    }
    if (scrolled.is_callable()) {
        Vector2 w = GetMouseWheelMoveV();
        if (w.x != 0.0f || w.y != 0.0f) {
            Value dx = Value((double)w.x);
            Value dy = Value((double)w.y);
            vm->call_value(scrolled, x, y, dx, dy);
        }
    }
}

// A new program must not inherit a button left "down" by the previous one, and the
// statiques survivent au VM (playground).
void mouse_reset() {
    s_down = false;
    s_last_click_time = -1.0f;
}

// The `mouse` module is an empty map: the user assigns pressed, released and moved to it, and
// mouse_poll reads them.
Value make_mouse_module() {
    return Value::make_map();
}
