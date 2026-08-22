#include "keyboard_module.h"
#include "value.h"
#include "vm.h"
#include <cctype>
#include <raylib.h>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// The GLFW keyboard is GLOBAL to the window: in the playground, typing or navigating in the
// editor would also feed the running graphical program. The page sets
// window.__ollinKbdBlocked = true when the EDITOR has focus, and we then ignore input on the game
// side. Outside the web there is no editor, so nothing is ever blocked.
//
// The flag is cached by keyboard_poll, once per frame: querying the DOM through EM_ASM on every
// isDown would be costly on a hot path.
static bool s_blocked = false;

static bool query_blocked() {
#ifdef __EMSCRIPTEN__
    return EM_ASM_INT({ return window.__ollinKbdBlocked ? 1 : 0; }) != 0;
#else
    return false;
#endif
}

// Functions are assigned to the `keyboard` module and the engine calls whichever exist, with no
// activation needed:
//   keyboard.keypressed = func(key) ... end   key pressed (an event)
//   keyboard.keyrelease = func(key) ... end   key released (an event)
// plus a HELD-state builtin, for continuous movement:
//   keyboard.isDown(key) -> whether the key is down right now.
// `key` is a key NAME: "a".."z", "0".."9", "space", "return", "escape", "backspace", "tab",
// "left"/"right"/"up"/"down", "shift"/"ctrl"/"alt", and so on.
//
// Detection happens in keyboard_poll(), called once per frame by the render loop
// (graphics_module.cpp), so the keyboard only works during a graphics.run(...) — or through the
// automatically called draw function.

// Readable name of a raylib key; "" when unhandled, and then ignored.
static std::string key_name(int key) {
    if (key >= KEY_A && key <= KEY_Z)
        return std::string(1, (char)('a' + (key - KEY_A)));
    if (key >= KEY_ZERO && key <= KEY_NINE)
        return std::string(1, (char)('0' + (key - KEY_ZERO)));
    switch (key) {
        case KEY_SPACE:                     return "space";
        case KEY_ENTER: case KEY_KP_ENTER:  return "return";
        case KEY_ESCAPE:                    return "escape";
        case KEY_BACKSPACE:                 return "backspace";
        case KEY_TAB:                       return "tab";
        case KEY_DELETE:                    return "delete";
        case KEY_LEFT:                      return "left";
        case KEY_RIGHT:                     return "right";
        case KEY_UP:                        return "up";
        case KEY_DOWN:                      return "down";
        case KEY_LEFT_SHIFT: case KEY_RIGHT_SHIFT:     return "shift";
        case KEY_LEFT_CONTROL: case KEY_RIGHT_CONTROL: return "ctrl";
        case KEY_LEFT_ALT: case KEY_RIGHT_ALT:         return "alt";
        default:                            return "";
    }
}

// A key name to a raylib keycode, the inverse of key_name; -1 when unknown.
static int key_code(std::string name) {
    for (char& c : name)
        c = (char)std::tolower((unsigned char)c);
    if (name.size() == 1) {
        char c = name[0];
        if (c >= 'a' && c <= 'z')
            return KEY_A + (c - 'a');
        if (c >= '0' && c <= '9')
            return KEY_ZERO + (c - '0');
        return -1;
    }
    if (name == "space")     return KEY_SPACE;
    if (name == "return" || name == "enter") return KEY_ENTER;
    if (name == "escape")    return KEY_ESCAPE;
    if (name == "backspace") return KEY_BACKSPACE;
    if (name == "tab")       return KEY_TAB;
    if (name == "delete")    return KEY_DELETE;
    if (name == "left")      return KEY_LEFT;
    if (name == "right")     return KEY_RIGHT;
    if (name == "up")        return KEY_UP;
    if (name == "down")      return KEY_DOWN;
    return -1;
}

// keyboard.isDown(key): is the key down right now? shift, ctrl and alt test both sides of the
// keyboard.
static int kbd_is_down(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (s_blocked)
        return ctx.ret(Value::make_bool(false));   // the editor has focus, so the game does not read the keyboard
    if (argc < 1 || !args[0].is_string())
        return ctx.ret(Value::make_bool(false));
    std::string name = args[0].as_string();
    for (char& c : name)
        c = (char)std::tolower((unsigned char)c);
    bool down = false;
    if (name == "shift")
        down = IsKeyDown(KEY_LEFT_SHIFT) || IsKeyDown(KEY_RIGHT_SHIFT);
    else if (name == "ctrl")
        down = IsKeyDown(KEY_LEFT_CONTROL) || IsKeyDown(KEY_RIGHT_CONTROL);
    else if (name == "alt")
        down = IsKeyDown(KEY_LEFT_ALT) || IsKeyDown(KEY_RIGHT_ALT);
    else {
        int code = key_code(name);
        if (code >= 0)
            down = IsKeyDown(code);
    }
    return ctx.ret(Value::make_bool(down));
}

// Keys currently held, so that keyrelease can be emitted. Indexed by raylib keycode (< 512), and
// zero-initialized by static lifetime.
static bool s_down[512];
// Was any key pressed during THIS frame? raylib's queue is drained right here, so another module
// cannot read it again and asks for this flag instead — sound opens on the user's first gesture,
// see audio_wake.
static bool s_pressed_any = false;

// Clears the held state. Called at the start of every gfx_run: on the shared WASM instance
// s_down is static and would otherwise survive from one run to the next, so a key held across a
// reset would produce a keyrelease with no keypressed.
void keyboard_reset() {
    for (int i = 0; i < 512; i++)
        s_down[i] = false;
}

bool keyboard_pressed_any() {
    return s_pressed_any;
}

void keyboard_poll() {
    s_pressed_any = false;
    s_blocked = query_blocked();   // refreshed once per frame, and read by is_down without querying the DOM again
    VM* vm = VM::current();
    Value kbd = vm->get_global("keyboard");
    Value pressed, released;
    if (kbd.is_map()) {
        pressed = kbd.map_get(Value(std::string("keypressed")));
        released = kbd.map_get(Value(std::string("keyrelease")));
    }
    bool want_press = pressed.is_callable();
    bool want_release = released.is_callable();

    if (s_blocked) {
        // The editor has focus, so the game no longer receives the keyboard. We RELEASE the keys
        // still tracked (keyrelease, then clear) so none stays stuck, and drain the press queue so
        // they are not replayed when input is unblocked.
        for (int k = 0; k < 512; k++) {
            if (!s_down[k])
                continue;
            s_down[k] = false;
            if (want_release) {
                std::string name = key_name(k);
                if (!name.empty())
                    vm->call_value(released, Value(name));
            }
        }
        while (GetKeyPressed() != 0) {
        }
        return;
    }

    // This frame's presses, taken from the key queue, which is robust to timing. We drain it and
    // track the held state even without a keypressed callback, for keyrelease's sake.
    int key;
    while ((key = GetKeyPressed()) != 0) {
        s_pressed_any = true;
        std::string name = key_name(key);
        if (name.empty())
            continue;
        if (key >= 0 && key < 512)
            s_down[key] = true;
        if (want_press)
            vm->call_value(pressed, Value(name));
    }

    // Releases: walk the keys tracked as held.
    for (int k = 0; k < 512; k++) {
        if (!s_down[k])
            continue;
        if (IsKeyReleased(k)) {
            s_down[k] = false;
            if (want_release) {
                std::string name = key_name(k);
                if (!name.empty())
                    vm->call_value(released, Value(name));
            }
        }
    }
}

// The `keyboard` module exposes isDown(); the user additionally assigns
// keypressed / keyrelease, lues par keyboardPoll().
Value make_keyboard_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("isDown")), Value::make_builtin(kbd_is_down));
    return m;
}
