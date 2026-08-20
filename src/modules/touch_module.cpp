#include "touch_module.h"
#include "value.h"
#include "vm.h"
#include <raylib.h>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Multitouche, build AVEC raylib.
//
// Tout le travail est un DIFF : raylib expose l'état courant (GetTouchPointCount,
// GetTouchPointId, GetTouchPosition) et rien d'autre. On garde donc la liste de l'image
// précédente et on la compare, ce qui donne les trois événements que le script attend.
//
// MAIS cette liste MENT dans deux cas, et le module ne peut pas la recopier telle quelle :
//
// 1. Deux doigts levés dans le MÊME événement. emscripten transmet l'UNION des doigts
//    encore posés (`e.touches`) et de ceux qui viennent de se lever (`e.changedTouches`),
//    et raylib, qui n'en retire qu'un seul par événement (il sort de sa boucle au premier),
//    laisse l'autre dans sa liste jusqu'au prochain événement tactile — parfois jamais.
// 2. Perte de focus (onglet changé, application quittée) : le navigateur n'envoie AUCUN
//    touchend, donc tous les doigts restent « posés » indéfiniment. `IsWindowFocused()` ne
//    suffit pas — MESURÉ : avec le seul test de focus, une note tenue continuait de sonner
//    après un `blur`.
//
// Dans les deux cas le script verrait un contact fantôme, et une note tenue par ce contact ne
// s'arrêterait plus. On écoute donc le navigateur — mais SEULEMENT pour retirer.
//
// SENS DU FILTRE, à ne pas inverser : le navigateur sert de preuve de LEVER, jamais
// d'autorisation de poser. Prendre sa liste de doigts posés pour la vérité et n'accepter que
// ce qu'elle contient a été essayé, et perdait des contacts encore appuyés sur un vrai
// téléphone : tout ce que cette liste ignore — un événement manqué, un identifiant que la
// couche graphique renumérote, un focus rapporté à faux le temps d'une barre d'adresse —
// devenait une annulation. Un doute doit laisser le doigt vivant ; seul un `touchend`, un
// `touchcancel` ou une perte de focus le tue.
//
// État des preuves, à ne pas confondre : la perte de focus est corrigée par MESURE (sans le
// filtre, une note tenue continue de sonner après un `blur` ; avec, elle s'arrête), et la
// non-régression l'est aussi (un contact absent des listes du navigateur reste vivant). Le
// lever simultané, lui, est couvert par CONSTRUCTION — l'identifiant levé est mémorisé — mais
// le harnais de test (événements tactiles synthétiques) ne le reproduit pas : raylib y rend le
// même compte que le navigateur.

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

#ifdef __EMSCRIPTEN__
// Écoute en CAPTURE sur window : on n'intercepte rien à raylib, qui garde ses propres écouteurs
// et son émulation de la souris. Deux ensembles, aux rôles bien distincts :
//   `poses` — miroir de `e.touches`, qui ne sert QU'À alimenter le second lors d'un blur ;
//   `leves` — les identifiants dont on a VU le lever, seul ensemble que le filtre consulte.
// Un identifiant sort de `leves` dès qu'un doigt se repose avec ce numéro : le navigateur les
// recycle, et sans cela le doigt suivant naîtrait déjà mort.
void install_dom_watch() {
    static bool pose = false;
    if (pose)
        return;
    pose = true;
    EM_ASM({
        if (window.__ollinTouchGone)
            return;
        window.__ollinTouchGone = new Set();
        window.__ollinTouchHeld = new Set();
        var poses = function(e) {
            var s = new Set();
            for (var i = 0; i < e.touches.length; i++) {
                s.add(e.touches[i].identifier);
                window.__ollinTouchGone.delete(e.touches[i].identifier);
            }
            window.__ollinTouchHeld = s;
        };
        var leves = function(e) {
            for (var i = 0; i < e.changedTouches.length; i++)
                window.__ollinTouchGone.add(e.changedTouches[i].identifier);
            poses(e);
        };
        // Pas de littéral de tableau ni d'objet ici : EM_ASM est une MACRO, et une virgule
        // hors parenthèses y sépare ses arguments — le bloc ne compile alors plus.
        var opt = { capture: true };
        opt.passive = true;
        var poses_noms = 'touchstart touchmove'.split(' ');
        for (var i = 0; i < poses_noms.length; i++)
            window.addEventListener(poses_noms[i], poses, opt);
        var leves_noms = 'touchend touchcancel'.split(' ');
        for (var i = 0; i < leves_noms.length; i++)
            window.addEventListener(leves_noms[i], leves, opt);
        // Perte de focus : aucun touchend n'arrive, donc on déclare levés tous les doigts que
        // l'on savait posés. C'est la seule raison d'être de `__ollinTouchHeld`.
        var abandonner = function() {
            window.__ollinTouchHeld.forEach(function(id) { window.__ollinTouchGone.add(id); });
            window.__ollinTouchHeld = new Set();
        };
        window.addEventListener('blur', abandonner);
        document.addEventListener('visibilitychange', function() {
            if (document.hidden)
                abandonner();
        });
    });
}

bool contact_vivant(int id) {
    return EM_ASM_INT({
        return (window.__ollinTouchGone && window.__ollinTouchGone.has($0)) ? 0 : 1;
    }, id) != 0;
}

// Un identifiant levé ne sert que tant que raylib le rapporte encore : passé ce point il n'y a
// plus de fantôme à filtrer. Sans cet oubli, l'ensemble grossirait pendant toute la session,
// le navigateur ne recyclant pas forcément ses identifiants.
void oublier_leves_absents(const int* ids, int n) {
    EM_ASM({
        if (!window.__ollinTouchGone || window.__ollinTouchGone.size === 0)
            return;
        var vus = new Set();
        for (var i = 0; i < $1; i++)
            vus.add(HEAP32[($0 >> 2) + i]);
        window.__ollinTouchGone.forEach(function(id) {
            if (!vus.has(id))
                window.__ollinTouchGone.delete(id);
        });
    }, ids, n);
}
#else
void install_dom_watch() {
}

// Hors navigateur, la liste de raylib est la seule source, et le cas des levers simultanés
// n'existe pas : le bureau ne rapporte aucun contact tactile.
bool contact_vivant(int) {
    return true;
}

void oublier_leves_absents(const int*, int) {
}
#endif

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

// count et points passent par le MÊME filtre que le suivi : un script qui lit l'état ne doit
// pas voir un contact que les rappels considèrent comme levé.
int contacts_vivants(Point* out) {
    int n = 0;
    // Pas de test de focus ici : `IsWindowFocused()` répond faux sur un vrai téléphone dès
    // qu'un ornement du navigateur prend la main, et coupait alors des doigts encore posés.
    // La perte de focus est traitée là où elle est certaine, par l'écouteur `blur`.
    int brut = GetTouchPointCount();
    if (brut > k_max_points)
        brut = k_max_points;
    int ids[k_max_points];
    for (int i = 0; i < brut; i++) {
        ids[i] = GetTouchPointId(i);
        if (!contact_vivant(ids[i]))
            continue;
        Vector2 p = GetTouchPosition(i);
        out[n].id = ids[i];
        out[n].x = p.x;
        out[n].y = p.y;
        n++;
    }
    oublier_leves_absents(ids, brut);
    return n;
}

int touch_count(CallCtx& ctx) {
    Point pts[k_max_points];
    install_dom_watch();
    return ctx.ret(Value((int64_t)contacts_vivants(pts)));
}

// Les contacts en cours, sous forme de tableau de {id, x, y} : de quoi dessiner un retour
// visuel ou piloter une manette à deux doigts sans passer par les rappels.
int touch_points(CallCtx& ctx) {
    Value arr = Value::make_array();
    Point pts[k_max_points];
    install_dom_watch();
    int n = contacts_vivants(pts);
    for (int i = 0; i < n; i++) {
        Value m = Value::make_map();
        m.map_set(Value(std::string("id")), Value((int64_t)pts[i].id));
        m.map_set(Value(std::string("x")), Value((double)pts[i].x));
        m.map_set(Value(std::string("y")), Value((double)pts[i].y));
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

    install_dom_watch();
    Point cur[k_max_points];
    int n = contacts_vivants(cur);

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
