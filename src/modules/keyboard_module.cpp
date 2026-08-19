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

static bool query_blocked() {
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

// Nom de touche → keycode raylib (inverse de keyName) ; -1 si inconnu.
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

// keyboard.isDown(key) : la touche est-elle enfoncée à cet instant ? true/false.
// shift/ctrl/alt testent les deux côtés du clavier.
static int kbd_is_down(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (s_blocked)
        return ctx.ret(Value::make_bool(false));   // éditeur focalisé → le jeu ne lit pas le clavier
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

// Touches actuellement enfoncées (pour émettre keyrelease). Indexé par keycode
// raylib (< 512). Zéro-initialisé (durée de vie statique).
static bool s_down[512];
// Une touche a-t-elle été enfoncée pendant CETTE frame ? La file de raylib est drainée
// ici même, donc un autre module ne peut pas la relire — il demande ce drapeau (le son
// s'ouvre au premier geste de l'utilisateur, cf. audio_wake).
static bool s_pressed_any = false;

// Remet l'état « enfoncé » à zéro. Appelé au début de chaque gfx_run : sur
// l'instance WASM partagée, s_down est statique et survivrait sinon d'un run au
// suivant (touche tenue à travers un reset → keyrelease sans keypressed).
void keyboard_reset() {
    for (int i = 0; i < 512; i++)
        s_down[i] = false;
}

bool keyboard_pressed_any() {
    return s_pressed_any;
}

void keyboard_poll() {
    s_pressed_any = false;
    s_blocked = query_blocked();   // rafraîchi 1×/frame ; lu par isDown sans re-interroger le DOM
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
        // Éditeur focalisé : le jeu ne reçoit plus le clavier. On RELÂCHE proprement les
        // touches encore suivies (keyrelease + clear) pour ne pas les laisser « coincées »,
        // et on draine la file d'appuis pour ne pas les rejouer au déblocage.
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

    // Appuis de la frame (file des touches — robuste au timing). On draine et on
    // suit l'état « enfoncé » même sans callback keypressed, pour keyrelease.
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

    // Relâchements : parcourt les touches suivies comme enfoncées.
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

// Le module `keyboard` expose isDown() ; l'utilisateur y affecte en plus
// keypressed / keyrelease, lues par keyboardPoll().
Value make_keyboard_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("isDown")), Value::make_builtin(kbd_is_down));
    return m;
}
