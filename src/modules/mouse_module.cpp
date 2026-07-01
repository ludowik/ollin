#include "value.h"
#include "vm.h"
#include "mouse_module.h"
#include <raylib.h>
#include <string>

// ── Pointeur (souris / tap tactile) ─────────────────────────────────────────
// On affecte des fonctions au module `mouse` ; le moteur les appelle si elles
// existent (aucune activation nécessaire), avec la position (x, y) dans le repère
// logique de la zone graphique :
//   mouse.pressed  = func(x, y) ... end   → appui du bouton gauche
//   mouse.released = func(x, y) ... end   → relâché
//   mouse.moved    = func(x, y) ... end   → déplacement du pointeur
//
// La détection a lieu dans mousePoll(), appelé une fois par frame par la boucle
// de rendu (raylib_module.cpp) — le pointeur ne fonctionne donc que pendant un
// graphics.run(...) (ou via la fonction draw auto-appelée).

void mousePoll() {
    VM* vm = VM::current();
    Value m = vm->getGlobal("mouse");
    if (!m.isMap())
        return;
    Value pressed = m.mapGet(Value(std::string("pressed")));
    Value released = m.mapGet(Value(std::string("released")));
    Value moved = m.mapGet(Value(std::string("moved")));
    if (!pressed.isCallable() && !released.isCallable() && !moved.isCallable())
        return;

    Value x = Value((int64_t)GetMouseX());
    Value y = Value((int64_t)GetMouseY());

    if (pressed.isCallable() && IsMouseButtonPressed(MOUSE_BUTTON_LEFT))
        vm->callValue(pressed, x, y);
    if (released.isCallable() && IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
        vm->callValue(released, x, y);
    if (moved.isCallable()) {
        Vector2 d = GetMouseDelta();
        if (d.x != 0.0f || d.y != 0.0f)
            vm->callValue(moved, x, y);
    }
}

// Le module `mouse` est une map vide : l'utilisateur y affecte pressed /
// released / moved, lues par mousePoll().
Value makeMouseModule() {
    return Value::makeMap();
}
