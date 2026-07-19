#include "mouse_module.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <string>
#include <cmath>

// ── Pointeur (souris / tap tactile) ─────────────────────────────────────────
// On affecte des fonctions au module `mouse` ; le moteur les appelle si elles
// existent (aucune activation nécessaire), avec la position (x, y) dans le repère
// logique de la zone graphique :
//   mouse.pressed  = func(x, y) ... end   → appui du bouton gauche
//   mouse.released = func(x, y) ... end   → relâché
//   mouse.moved    = func(x, y) ... end   → déplacement du pointeur
//
// La détection a lieu dans mousePoll(), appelé une fois par frame par la boucle
// de rendu (graphics_module.cpp) — le pointeur ne fonctionne donc que pendant un
// graphics.run(...) (ou via la fonction draw auto-appelée).

static float s_last_click_time = -1.0f;
static int   s_last_click_x    = -9999;
static int   s_last_click_y    = -9999;
static const float DBLCLICK_DELAY = 0.30f;
static const int   DBLCLICK_DIST  = 8;

void mousePoll() {
    VM* vm = VM::current();
    Value m = vm->getGlobal("mouse");
    if (!m.isMap())
        return;
    Value pressed       = m.mapGet(Value(std::string("pressed")));
    Value released      = m.mapGet(Value(std::string("released")));
    Value moved         = m.mapGet(Value(std::string("moved")));
    Value scrolled      = m.mapGet(Value(std::string("scrolled")));
    Value doubleClicked = m.mapGet(Value(std::string("doubleClicked")));

    int mx = GetMouseX();
    int my = GetMouseY();
    Value x = Value((int64_t)mx);
    Value y = Value((int64_t)my);

    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        float now = GetTime();
        bool dbl = doubleClicked.isCallable()
            && (now - s_last_click_time) < DBLCLICK_DELAY
            && std::abs(mx - s_last_click_x) < DBLCLICK_DIST
            && std::abs(my - s_last_click_y) < DBLCLICK_DIST;
        if (dbl) {
            vm->callValue(doubleClicked, x, y);
            s_last_click_time = -1.0f;   // reset pour ne pas déclencher en triple-clic
        } else {
            if (pressed.isCallable())
                vm->callValue(pressed, x, y);
            s_last_click_time = now;
            s_last_click_x    = mx;
            s_last_click_y    = my;
        }
    }
    if (released.isCallable() && IsMouseButtonReleased(MOUSE_BUTTON_LEFT))
        vm->callValue(released, x, y);
    if (moved.isCallable()) {
        Vector2 d = GetMouseDelta();
        if (d.x != 0.0f || d.y != 0.0f)
            vm->callValue(moved, x, y);
    }
    if (scrolled.isCallable()) {
        Vector2 w = GetMouseWheelMoveV();
        if (w.x != 0.0f || w.y != 0.0f) {
            Value dx = Value((double)w.x);
            Value dy = Value((double)w.y);
            vm->callValue(scrolled, x, y, dx, dy);
        }
    }
}

// Le module `mouse` est une map vide : l'utilisateur y affecte pressed /
// released / moved, lues par mousePoll().
Value makeMouseModule() {
    return Value::makeMap();
}
