#include "value.h"
#include "vm.h"
#include "mouse_module.h"
#include <raylib.h>
#include <stdexcept>
#include <string>

// ── Module mouse ──────────────────────────────────────────────────────────────
// Pointeur (souris ou tap tactile, unifiés par raylib sur le web). Un callback
// DÉDIÉ par type d'événement, chacun appelé avec la position (x, y) dans le
// repère logique de la zone graphique :
//   mouse.on_down(cb)  → cb(x, y) à l'appui du bouton gauche
//   mouse.on_up(cb)    → cb(x, y) au relâché
//   mouse.on_move(cb)  → cb(x, y) quand le pointeur se déplace
//   mouse.disable()    → oublie tous les callbacks
//
// La détection a lieu dans mousePoll(), appelé une fois par frame par la boucle
// de rendu (raylib_module.cpp) — le pointeur ne fonctionne donc que pendant un
// graphics.run(...).

static Value s_on_down;
static Value s_on_up;
static Value s_on_move;

void mousePoll() {
    if (!s_on_down.isCallable() && !s_on_up.isCallable() && !s_on_move.isCallable())
        return;
    // capture locale : un callback peut réenregistrer / désactiver
    Value down = s_on_down, up = s_on_up, move = s_on_move;
    VM* vm = VM::current();
    Value x = Value((int64_t)GetMouseX());
    Value y = Value((int64_t)GetMouseY());

    if (down.isCallable() && IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        vm->callValue(down, x, y);
    if (up.isCallable() && IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
        vm->callValue(up, x, y);
    if (move.isCallable()) {
        Vector2 d = GetMouseDelta();
        if (d.x != 0.0f || d.y != 0.0f)
            vm->callValue(move, x, y);
    }
}

// arg callable → enregistre ; nil → efface ; sinon erreur.
static Value setHandler(Value& slot, const char* who, Value* args, int argc) {
    if (argc < 1 || args[0].isNil()) { slot = Value{}; return Value{}; }
    if (!args[0].isCallable())
        throw std::runtime_error(std::string(who) + ": expected a callback function or nil");
    slot = args[0];
    return Value{};
}

static Value mouse_on_down(Value* args, int argc) { return setHandler(s_on_down, "mouse.on_down", args, argc); }
static Value mouse_on_up  (Value* args, int argc) { return setHandler(s_on_up,   "mouse.on_up",   args, argc); }
static Value mouse_on_move(Value* args, int argc) { return setHandler(s_on_move, "mouse.on_move", args, argc); }

static Value mouse_disable(Value* args, int argc) {
    (void)args; (void)argc;
    s_on_down = Value{};
    s_on_up   = Value{};
    s_on_move = Value{};
    return Value{};
}

Value makeMouseModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("on_down")), Value::makeBuiltin(mouse_on_down));
    m.mapSet(Value(std::string("on_up")),   Value::makeBuiltin(mouse_on_up));
    m.mapSet(Value(std::string("on_move")), Value::makeBuiltin(mouse_on_move));
    m.mapSet(Value(std::string("disable")), Value::makeBuiltin(mouse_disable));
    return m;
}
