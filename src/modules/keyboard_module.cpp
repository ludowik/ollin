#include "keyboard_module.h"
#include "value.h"
#include "vm.h"
#include <cctype>
#include <raylib.h>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Le clavier GLFW est GLOBAL (window) : dans le playground, taper/naviguer dans
// l'éditeur alimenterait aussi le programme graphique en cours. La page pose
// window.__ollinKbdBlocked=true quand l'ÉDITEUR a le focus → on ignore alors les
// entrées côté jeu. Hors web (natif), pas d'éditeur : jamais bloqué.
//
// Le drapeau est mis en cache par keyboardPoll (1×/frame) : interroger le DOM
// (EM_ASM) à chaque isDown serait coûteux (chemin chaud).
static bool s_blocked = false;

static bool queryBlocked() {
#ifdef __EMSCRIPTEN__
    return EM_ASM_INT({ return window.__ollinKbdBlocked ? 1 : 0; }) != 0;
#else
    return false;
#endif
}

// ── Clavier ─────────────────────────────────────────────────────────────────
// On affecte des fonctions au module `keyboard` ; le moteur les appelle si elles
// existent (aucune activation nécessaire) :
//   keyboard.keypressed = func(key) ... end   → touche enfoncée (événement)
//   keyboard.keyrelease = func(key) ... end   → touche relâchée (événement)
// Et un builtin d'état MAINTENU (pour un déplacement continu) :
//   keyboard.isDown(key) → true/false selon que la touche est enfoncée maintenant.
// `key` est un NOM de touche : "a".."z", "0".."9", "space", "return", "escape",
//   "backspace", "tab", "left"/"right"/"up"/"down", "shift"/"ctrl"/"alt", etc.
//
// La détection a lieu dans keyboardPoll(), appelé une fois par frame par la
// boucle de rendu (graphics_module.cpp) — le clavier ne fonctionne donc que
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

// Nom de touche → keycode raylib (inverse de keyName) ; -1 si inconnu.
static int keyCode(std::string name) {
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

// keyboard.isDown(key) : la touche est-elle enfoncée à cet instant ? true/false.
// shift/ctrl/alt testent les deux côtés du clavier.
static Value kbd_is_down(CallCtx& ctx) {
    Value* a = ctx.args; int n = ctx.argc;
    if (s_blocked)
        return Value((int64_t)0);   // éditeur focalisé → le jeu ne lit pas le clavier
    if (argc < 1 || !args[0].isString())
        return Value((int64_t)0);
    std::string name = args[0].asString();
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
        int code = keyCode(name);
        if (code >= 0)
            down = IsKeyDown(code);
    }
    return Value((int64_t)(down ? 1 : 0));
}

// Touches actuellement enfoncées (pour émettre keyrelease). Indexé par keycode
// raylib (< 512). Zéro-initialisé (durée de vie statique).
static bool s_down[512];

// Remet l'état « enfoncé » à zéro. Appelé au début de chaque gfx_run : sur
// l'instance WASM partagée, s_down est statique et survivrait sinon d'un run au
// suivant (touche tenue à travers un reset → keyrelease sans keypressed).
void keyboardReset() {
    for (int i = 0; i < 512; i++)
        s_down[i] = false;
}

void keyboardPoll() {
    s_blocked = queryBlocked();   // rafraîchi 1×/frame ; lu par isDown sans re-interroger le DOM
    VM* vm = VM::current();
    Value kbd = vm->getGlobal("keyboard");
    Value pressed, released;
    if (kbd.isMap()) {
        pressed = kbd.mapGet(Value(std::string("keypressed")));
        released = kbd.mapGet(Value(std::string("keyrelease")));
    }
    bool wantPress = pressed.isCallable();
    bool wantRelease = released.isCallable();

    if (s_blocked) {
        // Éditeur focalisé : le jeu ne reçoit plus le clavier. On RELÂCHE proprement les
        // touches encore suivies (keyrelease + clear) pour ne pas les laisser « coincées »,
        // et on draine la file d'appuis pour ne pas les rejouer au déblocage.
        for (int k = 0; k < 512; k++) {
            if (!s_down[k])
                continue;
            s_down[k] = false;
            if (wantRelease) {
                std::string name = keyName(k);
                if (!name.empty())
                    vm->callValue(released, Value(name));
            }
        }
        while (GetKeyPressed() != 0) {
        }
        return;
    }

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

// Le module `keyboard` expose isDown() ; l'utilisateur y affecte en plus
// keypressed / keyrelease, lues par keyboardPoll().
Value makeKeyboardModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("isDown")), Value::makeBuiltin(kbd_is_down));
    return m;
}
