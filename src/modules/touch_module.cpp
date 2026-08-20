#include "touch_module.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <string>

// Multitouche, build AVEC raylib.
//
// Tout le travail est un DIFF : raylib expose l'état courant (GetTouchPointCount,
// GetTouchPointId, GetTouchPosition) et rien d'autre. On garde donc la liste de l'image
// précédente et on la compare, ce qui donne les trois événements que le script attend.

namespace {

// raylib suit jusqu'à MAX_TOUCH_POINTS contacts (8 par défaut). La table est de taille fixe :
// un doigt de plus est simplement ignoré, comme le fait raylib lui-même.
constexpr int k_max_points = 8;

struct Point {
    int id = -1;
    float x = 0.0f;
    float y = 0.0f;
};

Point s_prev[k_max_points];
int s_prev_count = 0;

int index_of(const Point* liste, int n, int id) {
    for (int i = 0; i < n; i++) {
        if (liste[i].id == id)
            return i;
    }
    return -1;
}

Value callback(const Value& m, const char* nom) {
    return m.map_get(Value(std::string(nom)));
}

int touch_count(CallCtx& ctx) {
    int n = GetTouchPointCount();
    return ctx.ret(Value((int64_t)(n > k_max_points ? k_max_points : n)));
}

// Les contacts en cours, sous forme de tableau de {id, x, y} : de quoi dessiner un retour
// visuel ou piloter une manette à deux doigts sans passer par les rappels.
int touch_points(CallCtx& ctx) {
    Value arr = Value::make_array();
    int n = GetTouchPointCount();
    if (n > k_max_points)
        n = k_max_points;
    for (int i = 0; i < n; i++) {
        Vector2 p = GetTouchPosition(i);
        Value m = Value::make_map();
        m.map_set(Value(std::string("id")), Value((int64_t)GetTouchPointId(i)));
        m.map_set(Value(std::string("x")), Value((double)p.x));
        m.map_set(Value(std::string("y")), Value((double)p.y));
        arr.array_push(m);
    }
    return ctx.ret(arr);
}

} // namespace

void touch_poll() {
    VM* vm = VM::current();
    Value m = vm->get_global("touch");
    if (!m.is_map())
        return;
    Value began = callback(m, "began");
    Value moved = callback(m, "moved");
    Value ended = callback(m, "ended");

    Point cur[k_max_points];
    int n = GetTouchPointCount();
    if (n > k_max_points)
        n = k_max_points;
    for (int i = 0; i < n; i++) {
        Vector2 p = GetTouchPosition(i);
        cur[i].id = GetTouchPointId(i);
        cur[i].x = p.x;
        cur[i].y = p.y;
    }

    // Posés et déplacés : un identifiant absent de l'image précédente est un doigt nouveau.
    // Trois arguments passent par la forme générique de call_value : le VM n'offre pas de
    // surcharge à trois, et en ajouter une pour un seul appelant ne se justifie pas.
    for (int i = 0; i < n; i++) {
        int j = index_of(s_prev, s_prev_count, cur[i].id);
        Value args[3] = {Value((int64_t)cur[i].id), Value((double)cur[i].x), Value((double)cur[i].y)};
        if (j < 0) {
            if (began.is_callable())
                vm->call_value(began, args, 3);
        } else if (moved.is_callable() && (cur[i].x != s_prev[j].x || cur[i].y != s_prev[j].y)) {
            vm->call_value(moved, args, 3);
        }
    }

    // Levés : un identifiant de l'image précédente qui a disparu. On rend sa DERNIÈRE
    // position connue — celle du lever n'est plus lisible, raylib ayant retiré le point.
    for (int i = 0; i < s_prev_count; i++) {
        if (index_of(cur, n, s_prev[i].id) >= 0)
            continue;
        if (ended.is_callable()) {
            Value args[3] = {Value((int64_t)s_prev[i].id), Value((double)s_prev[i].x),
                             Value((double)s_prev[i].y)};
            vm->call_value(ended, args, 3);
        }
    }

    // La liste courante devient la référence de l'image suivante. Copiée APRÈS les appels :
    // un rappel du script peut lever une erreur, et l'état resterait alors cohérent.
    for (int i = 0; i < n; i++)
        s_prev[i] = cur[i];
    s_prev_count = n;
}

void touch_reset() {
    s_prev_count = 0;
}

// Le module est une map vide : le script y affecte began / moved / ended, et lit count /
// points. Même patron que `mouse`.
Value make_touch_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("count")), Value::make_builtin(touch_count));
    m.map_set(Value(std::string("points")), Value::make_builtin(touch_points));
    return m;
}
