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
//    laisse l'autre dans sa liste jusqu'au prochain événement tactile — parfois jamais. Ce
//    cas est couvert par CONSTRUCTION (l'identifiant levé est mémorisé) et NON par mesure :
//    le harnais de test, aux événements synthétiques, ne le reproduit pas.
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
// `touchcancel` ou une perte de focus le tue. La non-régression est MESURÉE : un contact que
// le navigateur ne mentionne plus dans aucune liste reste vivant.

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
//   `__ollinTouchHeld` — miroir de `e.touches`, qui ne sert QU'À alimenter le second au blur ;
//   `__ollinTouchGone` — les identifiants dont on a VU le lever, seul ensemble que le filtre lit.
// Un identifiant sort de `Gone` dès qu'un doigt se repose avec ce numéro : le navigateur les
// recycle, et sans cela le doigt suivant naîtrait déjà mort.
void install_dom_watch() {
    static bool pose = false;
    if (pose)
        return;
    pose = true;
    EM_ASM({
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
        var brancher = function(noms, fn) {
            var liste = noms.split(' ');
            for (var i = 0; i < liste.length; i++)
                window.addEventListener(liste[i], fn, opt);
        };
        brancher('touchstart touchmove', poses);
        brancher('touchend touchcancel', leves);
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

// UNE traversée de la frontière JavaScript par image : on passe les identifiants que raylib
// rapporte et l'on récupère, en un masque de bits, ceux dont le lever a été vu. Interroger
// l'ensemble contact par contact coûtait un aller-retour par doigt.
//
// Le même passage OUBLIE les identifiants levés que raylib ne rapporte plus : il n'y a alors
// plus de fantôme à filtrer, et sans cet oubli l'ensemble grossirait toute la session (le
// navigateur ne recycle pas forcément ses identifiants).
int leves_masque(const int* ids, int n) {
    return EM_ASM_INT({
        var partis = window.__ollinTouchGone;
        if (!partis)
            return 0;
        var masque = 0;
        var vus = new Set();
        for (var i = 0; i < $1; i++) {
            var id = HEAP32[($0 >> 2) + i];
            vus.add(id);
            if (partis.has(id))
                masque |= 1 << i;
        }
        partis.forEach(function(id) {
            if (!vus.has(id))
                partis.delete(id);
        });
        return masque;
    }, ids, n);
}

void oublier_tous_leves() {
    EM_ASM({
        if (window.__ollinTouchGone)
            window.__ollinTouchGone.clear();
    });
}
#else
void install_dom_watch() {
}

// Hors navigateur, la liste de raylib est la seule source, et le cas des levers simultanés
// n'existe pas : le bureau ne rapporte aucun contact tactile.
int leves_masque(const int*, int) {
    return 0;
}

void oublier_tous_leves() {
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

// Relevé filtré de l'image courante, établi UNE fois par `touch_begin_frame` : l'état que
// lisent `count` et `points` est exactement celui que les rappels ont vu.
Point s_cur[k_max_points];
int s_cur_count = 0;

void relever_contacts() {
    // Pas de test de focus ici : `IsWindowFocused()` répond faux sur un vrai téléphone dès
    // qu'un ornement du navigateur prend la main, et coupait alors des doigts encore posés.
    int brut = GetTouchPointCount();
    if (brut > k_max_points)
        brut = k_max_points;
    // Aucun contact rapporté : aucun fantôme possible, donc rien à filtrer et l'ensemble des
    // identifiants levés ne sert plus à rien. On ne franchit la frontière qu'à la TRANSITION,
    // sans quoi une image sans le moindre doigt — la quasi-totalité d'un programme — paierait
    // un aller-retour pour recevoir un masque nul.
    if (brut == 0) {
        s_cur_count = 0;
        if (s_prev_count > 0)
            oublier_tous_leves();
        return;
    }
    int ids[k_max_points];
    for (int i = 0; i < brut; i++)
        ids[i] = GetTouchPointId(i);
    int leves = leves_masque(ids, brut);
    s_cur_count = 0;
    for (int i = 0; i < brut; i++) {
        if (leves & (1 << i))
            continue;
        Vector2 p = GetTouchPosition(i);
        s_cur[s_cur_count].id = ids[i];
        s_cur[s_cur_count].x = p.x;
        s_cur[s_cur_count].y = p.y;
        s_cur_count++;
    }
}

int touch_count(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)s_cur_count));
}

// Les contacts en cours, sous forme de tableau de {id, x, y} : de quoi dessiner un retour
// visuel ou piloter une manette à deux doigts sans passer par les rappels.
int touch_points(CallCtx& ctx) {
    // Clés internées une fois : un script qui lit `points()` à chaque image pour dessiner un
    // retour visuel construisait sinon trois chaînes par contact et par appel.
    static const Value K_ID(std::string("id")), K_X(std::string("x")), K_Y(std::string("y"));
    Value arr = Value::make_array();
    for (int i = 0; i < s_cur_count; i++) {
        Value m = Value::make_map();
        m.map_set(K_ID, Value((int64_t)s_cur[i].id));
        m.map_set(K_X, Value((double)s_cur[i].x));
        m.map_set(K_Y, Value((double)s_cur[i].y));
        arr.array_push(m);
    }
    return ctx.ret(arr);
}

} // namespace

// Le relevé est une étape de la frame À PART ENTIÈRE, et non le début de `touch_poll` : les
// rappels de `mouse` s'exécutent AVANT, et beaucoup interrogent `touch.count()` pour savoir si
// le geste vient d'un doigt (le système émule la souris sur un doigt unique). Relever dans
// `touch_poll` rendait donc cette lecture en retard d'une image — un doigt posé y était vu
// comme « aucun contact », et l'émulation de la souris s'attribuait le geste (constaté :
// l'archet de `sound_demo` ne suivait plus le doigt).
void touch_begin_frame() {
    install_dom_watch();
    relever_contacts();
}

void touch_poll() {
    VM* vm = VM::current();
    Value m = vm->get_global("touch");
    if (!m.is_map())
        return;
    Value began = callback(m, "began");
    Value moved = callback(m, "moved");
    Value ended = callback(m, "ended");

    // Posés et déplacés : un identifiant absent de l'image précédente est un doigt nouveau.
    // Trois arguments passent par la forme générique de call_value : le VM n'offre pas de
    // surcharge à trois, et en ajouter une pour un seul appelant ne se justifie pas.
    for (int i = 0; i < s_cur_count; i++) {
        int j = index_of(s_prev, s_prev_count, s_cur[i].id);
        Value args[3] = {Value((int64_t)s_cur[i].id), Value((double)s_cur[i].x), Value((double)s_cur[i].y)};
        if (j < 0) {
            if (began.is_callable())
                vm->call_value(began, args, 3);
        } else if (moved.is_callable() && (s_cur[i].x != s_prev[j].x || s_cur[i].y != s_prev[j].y)) {
            vm->call_value(moved, args, 3);
        }
    }

    // Levés : un identifiant de l'image précédente qui a disparu. On rend sa DERNIÈRE
    // position connue — celle du lever n'est plus lisible, raylib ayant retiré le point.
    for (int i = 0; i < s_prev_count; i++) {
        if (index_of(s_cur, s_cur_count, s_prev[i].id) >= 0)
            continue;
        if (ended.is_callable()) {
            Value args[3] = {Value((int64_t)s_prev[i].id), Value((double)s_prev[i].x),
                             Value((double)s_prev[i].y)};
            vm->call_value(ended, args, 3);
        }
    }

    // La liste courante devient la référence de l'image suivante. Copiée APRÈS les appels :
    // un rappel du script peut lever une erreur, et l'état resterait alors cohérent.
    for (int i = 0; i < s_cur_count; i++)
        s_prev[i] = s_cur[i];
    s_prev_count = s_cur_count;
}

void touch_reset() {
    s_prev_count = 0;
    s_cur_count = 0;
}

// Le module est une map vide : le script y affecte began / moved / ended, et lit count /
// points. Même patron que `mouse`.
Value make_touch_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("count")), Value::make_builtin(touch_count));
    m.map_set(Value(std::string("points")), Value::make_builtin(touch_points));
    return m;
}
