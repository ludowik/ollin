#include "value.h"
#include "vm.h"
#include "keyboard_module.h"
#include <raylib.h>
#include <stdexcept>
#include <string>

// ── Module keyboard ───────────────────────────────────────────────────────────
// keyboard.enable(callback) : active la capture clavier. À chaque touche
//   détectée pendant la boucle de rendu, le callback Ollin est appelé avec une
//   chaîne : le caractère pour les touches imprimables, sinon un nom
//   ("space", "return", "escape", "backspace").
// keyboard.disable() : désactive la capture et oublie le callback.
//
// La détection a lieu dans keyboardPoll(), appelé une fois par frame par la
// boucle de rendu (raylib_module.cpp) — le clavier ne fonctionne donc que
// pendant un graphics.run(...).

static bool  s_enabled = false;
static Value s_callback;   // fonction Ollin (retenue par copie)

void keyboardPoll() {
    if (!s_enabled || !s_callback.isCallable()) return;
    Value cb = s_callback;   // capture : le callback peut appeler disable()
    VM* vm = VM::current();

    // Touches nommées via la FILE des touches pressées (robuste au timing, comme
    // la file des caractères ; IsKeyPressed serait basé sur l'état par frame et
    // raterait un appui/relâché survenu entre deux frames). Les imprimables sont
    // ignorées ici — elles passent par GetCharPressed ci-dessous.
    int key;
    while ((key = GetKeyPressed()) != 0) {
        const char* name = nullptr;
        switch (key) {
            case KEY_SPACE:                   name = "space";     break;
            case KEY_ENTER: case KEY_KP_ENTER: name = "return";    break;
            case KEY_ESCAPE:                  name = "escape";    break;
            case KEY_BACKSPACE:               name = "backspace"; break;
            default: break;
        }
        if (name) vm->callValue(cb, Value(std::string(name)));
    }

    // Caractères imprimables (file d'attente raylib, dans l'ordre de frappe).
    int c;
    while ((c = GetCharPressed()) != 0) {
        if (c == ' ') continue;   // espace déjà émis comme "space"
        int sz = 0;
        const char* u = CodepointToUTF8(c, &sz);
        vm->callValue(cb, Value(std::string(u, sz)));
    }
}

static Value kbd_enable(Value* args, int argc) {
    if (argc < 1 || !args[0].isCallable())
        throw std::runtime_error("keyboard.enable: expected a callback function");
    s_callback = args[0];
    s_enabled  = true;
    return Value{};
}

static Value kbd_disable(Value* args, int argc) {
    (void)args; (void)argc;
    s_enabled  = false;
    s_callback = Value{};   // release
    return Value{};
}

Value makeKeyboardModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("enable")),  Value::makeBuiltin(kbd_enable));
    m.mapSet(Value(std::string("disable")), Value::makeBuiltin(kbd_disable));
    return m;
}
