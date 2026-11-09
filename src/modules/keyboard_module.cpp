#include "keyboard_module.h"
#include "module_utils.h"
#include "ui_module.h"
#include "utf8.h"
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
//   keyboard.typed = func(text) ... end       text typed (an event): what the keys PRODUCE, which a key name cannot say
//   keyboard.show() / keyboard.hide()         the keyboard of a phone, which a canvas cannot raise by itself
// plus a HELD-state builtin, for continuous movement:
//   keyboard.isDown(key) -> whether the key is down right now.
// `key` is a key NAME: "a".."z", "0".."9", "space", "return", "escape", "backspace", "tab",
// "left"/"right"/"up"/"down", "shift"/"ctrl"/"alt", "f1".."f12", and so on.
// `text` is the characters the keyboard layout and the system made of the presses of the frame, in UTF-8: an accent,
// a hyphen, an apostrophe, a capital, a dead key's result. A fast typist or a paste gives several characters in one
// call. Control characters (return, tab, backspace) are never part of it: they are key names, for keypressed.
// While a ui text field is edited it takes the text and the control keys instead (ui_editing, ui_module.h), and neither
// typed nor keypressed is called.
// On a phone the text comes from an invisible element of the page that holds the focus (docs/lib/pg-text-input.js): the
// reasons, and what a browser accepts, are written there. On a computer it comes from raylib's character queue.
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
    if (key >= KEY_F1 && key <= KEY_F12)
        return "f" + std::to_string(key - KEY_F1 + 1);
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
    for (int n = 1; n <= 12; n++) {
        if (name == "f" + std::to_string(n))
            return KEY_F1 + (n - 1);
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
    if (s_blocked || ui_editing())
        return ctx.ret(Value::make_bool(false));   // the editor has focus, or a ui text field does: the program does not read the keyboard
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

// The text the frame's character queue holds, in UTF-8, without the control characters: raylib reports the characters
// the system produced, and some platforms include the ones that keys such as return or backspace make.
static std::string take_typed() {
    std::string text;
    int codepoint;
    while ((codepoint = GetCharPressed()) != 0) {
        if (codepoint < 32 || codepoint == 127)
            continue;
        utf8_encode((uint32_t)codepoint, text);
    }
    return text;
}

// What the page's invisible text element handed over this frame. `active` is false when the element is not the source of
// text (no phone, no tap yet, or a build outside the browser): the engine then reads raylib's own queue.
struct HostText {
    bool active = false;
    std::string text;
};

// Also tells the page whether the program wants text at all (it declared keyboard.typed), since that is what makes the
// page take the focus when the canvas is touched.
static HostText host_text(bool wanted) {
    HostText host;
#ifdef __EMSCRIPTEN__
    int len = -1;
    char* p = (char*)EM_ASM_INT(
        {
            var t = window.__ollinTextInput;
            if (!t) {
                HEAP32[$1 >> 2] = -1;
                return 0;
            }
            var s = t.frame($0 != 0);
            if (s === null) {
                HEAP32[$1 >> 2] = -1;
                return 0;
            }
            if (s === '') {
                HEAP32[$1 >> 2] = 0;
                return 0;
            }
            var bytes = new TextEncoder().encode(s);
            var ptr = _malloc(bytes.length + 1);
            if (!ptr) {
                HEAP32[$1 >> 2] = 0;
                return 0;
            }
            HEAPU8.set(bytes, ptr);
            HEAPU8[ptr + bytes.length] = 0;
            HEAP32[$1 >> 2] = bytes.length;
            return ptr;
        },
        wanted ? 1 : 0, &len);
    host.active = len >= 0;
    if (p) {
        host.text.assign(p, (size_t)len);
        free(p);
    }
#else
    (void)wanted;
#endif
    return host;
}

void keyboard_show() {
#ifdef __EMSCRIPTEN__
    EM_ASM({
        var t = window.__ollinTextInput;
        if (t)
            t.show();
    });
#endif
}

void keyboard_hide() {
#ifdef __EMSCRIPTEN__
    EM_ASM({
        var t = window.__ollinTextInput;
        if (t)
            t.hide();
    });
#endif
}

bool keyboard_dismissed() {
#ifdef __EMSCRIPTEN__
    return EM_ASM_INT({
        var t = window.__ollinTextInput;
        return t && t.takeDismissed() ? 1 : 0;
    }) != 0;
#else
    return false;
#endif
}

// keyboard.trace([lines]): the last lines of what the page saw of the phone's keyboard, newest last — the focus it took
// and lost, the keys it sent, the size of the visible area. A diagnostic for a device out of reach; "" outside the browser.
static int kbd_trace(CallCtx& ctx) {
    int count = 12;
    if (ctx.argc > 0 && ctx.args[0].is_number())
        count = (int)ctx.args[0].as_num();
    std::string text;
#ifdef __EMSCRIPTEN__
    char* p = (char*)EM_ASM_INT(
        {
            var t = window.__ollinTextInput;
            var s = t ? t.trace($0) : '';
            var bytes = new TextEncoder().encode(s);
            var ptr = _malloc(bytes.length + 1);
            if (!ptr)
                return 0;
            HEAPU8.set(bytes, ptr);
            HEAPU8[ptr + bytes.length] = 0;
            return ptr;
        },
        count);
    if (p) {
        text = p;
        free(p);
    }
#else
    (void)count;
#endif
    return ctx.ret(Value(text));
}

static int kbd_show(CallCtx& ctx) {
    keyboard_show();
    return ctx.ret(Value());
}

static int kbd_hide(CallCtx& ctx) {
    keyboard_hide();
    return ctx.ret(Value());
}

// Clears the held state. Called at the start of every gfx_run: on the shared WASM instance
// s_down is static and would otherwise survive from one run to the next, so a key held across a
// reset would produce a keyrelease with no keypressed.
void keyboard_reset() {
    for (int i = 0; i < 512; i++)
        s_down[i] = false;
#ifdef __EMSCRIPTEN__
    EM_ASM({
        var t = window.__ollinTextInput;
        if (t)
            t.reset();
    });
#endif
}

bool keyboard_pressed_any() {
    return s_pressed_any;
}

void keyboard_poll() {
    s_pressed_any = false;
    s_blocked = query_blocked();   // refreshed once per frame, and read by is_down without querying the DOM again
    VM* vm = VM::current();
    Value kbd = vm->get_global("keyboard");
    Value pressed, released, typed;
    if (kbd.is_map()) {
        pressed = kbd.map_get(Value(std::string("keypressed")));
        released = kbd.map_get(Value(std::string("keyrelease")));
        typed = kbd.map_get(Value(std::string("typed")));
    }
    HostText host = host_text(typed.is_callable() || ui_wants_text());
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
        take_typed();
        return;
    }

    // The text of the frame. raylib's queue is drained even without a callback, so that it does not hold what was typed
    // before the script asked, and even when the page's element is the source: both see the same keys, and reading both
    // would give every character twice.
    std::string text = take_typed();
    if (host.active)
        text = host.text;
    // A ui text field takes the text BEFORE the keys of the frame: the order between the two is lost, and "abc" then return
    // must not validate an empty draft.
    if (!text.empty() && ui_edit_text(text))
        text.clear();

    // This frame's presses, taken from the key queue, which is robust to timing. We drain it and
    // track the held state even without a keypressed callback, for keyrelease's sake.
    int key;
    while ((key = GetKeyPressed()) != 0) {
        s_pressed_any = true;
        std::string name = key_name(key);
        if (name.empty())
            continue;
        // A ui text field takes the keys while it is edited: the program sees neither the press nor, later, a release.
        if (ui_edit_key(name))
            continue;
        if (key >= 0 && key < 512)
            s_down[key] = true;
        if (want_press)
            vm->call_value(pressed, Value(name));
    }

    // The script's text comes after the presses it came from.
    if (!text.empty() && typed.is_callable())
        vm->call_value(typed, Value(text));

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
// keypressed / keyrelease, read by keyboard_poll().
Value make_keyboard_module() {
    return MapBuilder()
        .fn("isDown", kbd_is_down)
        .fn("show", kbd_show)
        .fn("hide", kbd_hide)
        .fn("trace", kbd_trace)
        .done();
}
