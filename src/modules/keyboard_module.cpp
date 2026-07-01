#include "value.h"
#include "vm.h"
#include "keyboard_module.h"
#include <raylib.h>
#include <string>

// ── Clavier ─────────────────────────────────────────────────────────────────
// Modèle « fonctions globales appelées par le moteur » (comme setup/update/draw) :
//   func keypressed(key)  → appelée à chaque touche enfoncée (si définie)
//   func keyrelease(key)  → appelée à chaque touche relâchée (si définie)
// `key` est un NOM de touche : "a".."z", "0".."9", "space", "return", "escape",
//   "backspace", "tab", "left"/"right"/"up"/"down", "shift"/"ctrl"/"alt", etc.
// Aucune activation nécessaire : il suffit de définir la (les) fonction(s).
//
// La détection a lieu dans keyboardPoll(), appelé une fois par frame par la
// boucle de rendu (raylib_module.cpp) — le clavier ne fonctionne donc que
// pendant un graphics.run(...) (ou via la fonction draw auto-appelée).

// Nom lisible d'une touche raylib ; "" si non gérée (ignorée).
static std::string keyName(int key) {
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

// Touches actuellement enfoncées (pour émettre keyrelease). Indexé par keycode
// raylib (< 512). Zéro-initialisé (durée de vie statique).
static bool s_down[512];

void keyboardPoll() {
    VM* vm = VM::current();
    Value pressed = vm->getGlobal("keypressed");
    Value released = vm->getGlobal("keyrelease");
    bool wantPress = pressed.isCallable();
    bool wantRelease = released.isCallable();

    // Appuis de la frame (file des touches — robuste au timing). On draine et on
    // suit l'état « enfoncé » même sans callback keypressed, pour keyrelease.
    int key;
    while ((key = GetKeyPressed()) != 0) {
        std::string name = keyName(key);
        if (name.empty())
            continue;
        if (key >= 0 && key < 512)
            s_down[key] = true;
        if (wantPress)
            vm->callValue(pressed, Value(name));
    }

    // Relâchements : parcourt les touches suivies comme enfoncées.
    for (int k = 0; k < 512; k++) {
        if (!s_down[k])
            continue;
        if (IsKeyReleased(k)) {
            s_down[k] = false;
            if (wantRelease) {
                std::string name = keyName(k);
                if (!name.empty())
                    vm->callValue(released, Value(name));
            }
        }
    }
}

// Le module `keyboard` n'expose plus de fonction : le clavier est piloté par les
// globales keypressed / keyrelease. Conservé (map vide) pour la cohérence des
// modules injectés.
Value makeKeyboardModule() {
    return Value::makeMap();
}
