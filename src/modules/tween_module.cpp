#include "tween_module.h"
#include "module_utils.h"
#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

// Module `tween` : fait évoluer un champ d'objet (ou une variable passée par `ref`) de sa
// valeur COURANTE vers une valeur cible, sur une durée, selon une courbe.
//
// Le moteur avance les tweens à chaque frame (tween_update_all) : rien à câbler dans
// draw(), et c'est la raison d'être d'un module natif — une classe Ollin devrait réclamer
// un appel par frame, dont l'oubli est le premier bug d'une bibliothèque de ce genre.
//
// Aucune dépendance graphique : le module tourne à l'identique en natif headless, où
// tween.update(dt) le pilote à la main (tests).

namespace {

// ── Courbes ─────────────────────────────────────────────────────────────────────
// Toutes prennent et rendent une progression normalisée sur [0;1]. Les noms exposés
// vivent dans des littéraux de chaîne, donc en camelCase comme le reste de l'API Ollin.

double ease_linear(double t) {
    return t;
}

double ease_in_quad(double t) {
    return t * t;
}

double ease_out_quad(double t) {
    return t * (2.0 - t);
}

double ease_in_out_quad(double t) {
    return t < 0.5 ? 2.0 * t * t : 1.0 - 2.0 * (1.0 - t) * (1.0 - t);
}

double ease_in_cubic(double t) {
    return t * t * t;
}

double ease_out_cubic(double t) {
    double u = 1.0 - t;
    return 1.0 - u * u * u;
}

double ease_in_out_cubic(double t) {
    if (t < 0.5)
        return 4.0 * t * t * t;
    double u = 1.0 - t;
    return 1.0 - 4.0 * u * u * u;
}

double ease_in_sine(double t) {
    return 1.0 - std::cos(t * 1.5707963267948966);
}

double ease_out_sine(double t) {
    return std::sin(t * 1.5707963267948966);
}

double ease_in_out_sine(double t) {
    return 0.5 * (1.0 - std::cos(t * 3.141592653589793));
}

double ease_in_expo(double t) {
    return t <= 0.0 ? 0.0 : std::pow(2.0, 10.0 * t - 10.0);
}

double ease_out_expo(double t) {
    return t >= 1.0 ? 1.0 : 1.0 - std::pow(2.0, -10.0 * t);
}

double ease_in_out_expo(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    if (t < 0.5)
        return 0.5 * std::pow(2.0, 20.0 * t - 10.0);
    return 1.0 - 0.5 * std::pow(2.0, 10.0 - 20.0 * t);
}

// Le dépassement de `back` vient de la constante 1,70158 du modèle de Penner.
double ease_in_back(double t) {
    return t * t * (2.70158 * t - 1.70158);
}

double ease_out_back(double t) {
    double u = t - 1.0;
    return 1.0 + u * u * (2.70158 * u + 1.70158);
}

double ease_in_out_back(double t) {
    const double c = 1.70158 * 1.525;
    if (t < 0.5)
        return 0.5 * (4.0 * t * t * ((c + 1.0) * 2.0 * t - c));
    double u = 2.0 * t - 2.0;
    return 0.5 * (u * u * ((c + 1.0) * u + c) + 2.0);
}

double ease_out_elastic(double t) {
    if (t <= 0.0)
        return 0.0;
    if (t >= 1.0)
        return 1.0;
    return std::pow(2.0, -10.0 * t) * std::sin((10.0 * t - 0.75) * 2.0943951023931953) + 1.0;
}

double ease_out_bounce(double t) {
    const double n = 7.5625;
    const double d = 2.75;
    if (t < 1.0 / d)
        return n * t * t;
    if (t < 2.0 / d) {
        double u = t - 1.5 / d;
        return n * u * u + 0.75;
    }
    if (t < 2.5 / d) {
        double u = t - 2.25 / d;
        return n * u * u + 0.9375;
    }
    double u = t - 2.625 / d;
    return n * u * u + 0.984375;
}

struct CurveEntry {
    const char* name;
    double (*fn)(double);
};

const CurveEntry k_curves[] = {
    {"linear", ease_linear},
    {"easeInQuad", ease_in_quad},
    {"easeOutQuad", ease_out_quad},
    {"easeInOutQuad", ease_in_out_quad},
    {"easeInCubic", ease_in_cubic},
    {"easeOutCubic", ease_out_cubic},
    {"easeInOutCubic", ease_in_out_cubic},
    {"easeInSine", ease_in_sine},
    {"easeOutSine", ease_out_sine},
    {"easeInOutSine", ease_in_out_sine},
    {"easeInExpo", ease_in_expo},
    {"easeOutExpo", ease_out_expo},
    {"easeInOutExpo", ease_in_out_expo},
    {"easeInBack", ease_in_back},
    {"easeOutBack", ease_out_back},
    {"easeInOutBack", ease_in_out_back},
    {"easeOutElastic", ease_out_elastic},
    {"easeOutBounce", ease_out_bounce},
};

const int k_curve_default = 3;   // easeInOutQuad

std::string curve_names() {
    std::string s;
    for (const auto& c : k_curves) {
        if (!s.empty())
            s += ", ";
        s += c.name;
    }
    return s;
}

int curve_index(const std::string& name, const char* fn) {
    for (int i = 0; i < (int)(sizeof(k_curves) / sizeof(k_curves[0])); i++) {
        if (name == k_curves[i].name)
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": courbe inconnue '" + name + "' — disponibles : " + curve_names());
}

// ── État ────────────────────────────────────────────────────────────────────────

// Un canal = UN champ numérique animé. Une cible structurée (un Color, un Vec2) en
// produit un par composante, si bien que le reste du module ne connaît que des nombres.
struct Chan {
    Value holder;   // map/instance dont on écrit la clé ; nil quand la cible est une `ref`
    Value ref;      // référence (`ref x`) ; nil quand holder est posé
    Value key;
    double from = 0.0;
    double to = 0.0;
    bool integral = false;   // départ ET cible entiers → on arrondit (pas de dérive en float)
};

// Une ÉTAPE de la suite : les canaux qu'elle anime, sa durée et sa courbe. Une étape sans
// canal est une attente pure (`{delay: 0.2}` dans une séquence). `tween.to` et `tween.value`
// créent une suite d'UNE étape : tout le module ne connaît donc qu'un seul chemin, et une
// séquence n'est pas un cas particulier.
struct Etape {
    std::vector<Chan> chans;
    bool attente = false;   // étape déclarée sans `to` : elle ne fait que laisser passer du temps
    bool demarree = false;  // bornes déjà lues ? (au PREMIER passage seulement — un retour
                            // rejoue les mêmes bornes, sinon il ne va nulle part)
    double dur = 0.0;
    int curve = k_curve_default;
    Value curve_fn;   // courbe fournie par le script (prioritaire sur `curve`)
};

// Plan de LECTURE : un segment par parcours de la SUITE, +1 dans le sens déclaré,
// -1 en arrière. `repeat(n)` répète la liste ; son second paramètre y ajoute le miroir de
// tout le plan (liste renversée, sens inversés). Deux appels COMPOSENT, chacun agissant sur
// le plan construit jusque-là, donc l'ordre compte :
//   .repeat(2)                    → +1 +1          (deux allers)
//   .repeat(2, true)              → +1 +1 -1 -1    (deux allers, puis les deux retours)
//   .repeat(nil, true).repeat(2)  → +1 -1 +1 -1    (deux allers-retours)
// Un plan vide n'existe pas : tout tween démarre avec un segment. Un segment de sens -1
// rejoue les étapes en ordre INVERSE, chacune à l'envers.
struct Tw {
    std::vector<Etape> etapes;
    size_t pos = 0;      // étape en cours, comptée dans l'ordre du segment courant
    std::vector<int8_t> plan{1};
    size_t seg = 0;      // segment en cours dans le plan
    bool endless = false;   // le plan est rejoué sans fin (loop)
    double elapsed = 0.0;
    double delay = 0.0;
    Value on_done;
    bool paused = false;
    bool alive = false;
    uint64_t born_pass = 0;   // passe d'avancement où le tween est né (cf. advance)
    uint32_t gen = 1;   // incrémentée à la libération → un handle périmé est détecté
};

std::vector<Tw> s_tweens;
std::vector<int> s_free;
bool s_engine_driven = false;
// Numéro de la passe d'avancement en cours. Un tween déclaré PENDANT une passe (par une
// courbe ou un rappel) ne doit pas y être avancé : il consommerait un pas de temps
// antérieur à sa naissance. Sans ce compteur, le résultat dépendrait du slot obtenu —
// au-dessus de l'index courant il était avancé, sur un slot recyclé plus bas il ne
// l'était pas.
uint64_t s_pass = 0;

void advance(double dt);

// Durée d'un parcours complet de la suite (identique dans les deux sens).
double duree_cycle(const Tw& t) {
    double d = 0.0;
    for (const auto& e : t.etapes)
        d += e.dur;
    return d;
}

// Index RÉEL de la k-ième étape du segment courant : un segment de sens -1 rejoue la suite
// en ordre inverse, donc la k-ième jouée est l'avant-dernière, etc.
size_t etape_index(const Tw& t, size_t k) {
    return t.plan[t.seg] > 0 ? k : t.etapes.size() - 1 - k;
}

bool tween_alive(int slot, uint32_t gen) {
    return slot >= 0 && slot < (int)s_tweens.size() && s_tweens[slot].alive && s_tweens[slot].gen == gen;
}

int alloc_tween() {
    int slot;
    if (!s_free.empty()) {
        slot = s_free.back();
        s_free.pop_back();
    } else {
        s_tweens.push_back(Tw{});
        slot = (int)s_tweens.size() - 1;
    }
    Tw& t = s_tweens[slot];
    uint32_t gen = t.gen;
    t = Tw{};
    t.gen = gen;
    t.alive = true;
    t.born_pass = s_pass;
    return slot;
}

void free_tween(int slot) {
    Tw& t = s_tweens[slot];
    t.alive = false;
    t.gen++;
    t.etapes.clear();      // relâche les Value retenues : sans cela le module garderait
    t.on_done = Value{};   // l'objet animé vivant longtemps après la fin de l'animation
    s_free.push_back(slot);
}

// ── Handles côté script : instance de classe native portant {slot, gen} ─────────
// Jamais un pointeur : déclarer un tween depuis un rappel de fin fait push_back sur
// s_tweens, ce qui invaliderait toute référence conservée.

Value tween_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), tween_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)s_tweens[slot].gen));
    return h;
}

// Slot d'un handle, ou -1 si le tween est terminé/annulé (un handle périmé n'est PAS une
// faute : garder le handle d'une animation finie est normal).
int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a tween");
    if (!tween_alive((int)slot.as_int(), (uint32_t)gen.as_int()))
        return -1;
    return (int)slot.as_int();
}

// ── Construction des canaux ─────────────────────────────────────────────────────

bool is_object(const Value& v) {
    return v.is_map() || v.is_class();
}

// Champs numériques communs à deux instances de MÊME classe (Color → r,g,b,a ; un Vec2
// utilisateur → x,y). L'interpolation est donc structurelle : aucun type n'est câblé ici.
// Écrit DANS l'instance courante (`cur`), qui joue elle-même le rôle de holder : le tween
// modifie l'objet, il ne le remplace pas.
void add_struct_chans(std::vector<Chan>& out, const Value& cur, const Value& tgt, const std::string& field,
                      const char* fn) {
    Value cls_a = cur.map_get(Value(std::string("__class__")));
    Value cls_b = tgt.map_get(Value(std::string("__class__")));
    if (cls_a.is_nil() || !cls_b.is_class() || cls_a.as_map() != cls_b.as_map()) {
        throw std::runtime_error(std::string(fn) + ": '" + field +
                                 "' : les deux valeurs doivent être des instances de la même classe");
    }
    int added = 0;
    for (const auto& kv : tgt.as_map()->data) {
        if (!kv.second.is_number() || !kv.first.is_string())
            continue;
        Value from = cur.map_get(kv.first);
        if (!from.is_number())
            continue;
        Chan c;
        c.holder = cur;   // on écrit DANS l'instance : le tween modifie l'objet, il ne le remplace pas
        c.key = kv.first;
        c.from = from.as_num();
        c.to = kv.second.as_num();
        c.integral = from.is_integer() && kv.second.is_integer();
        out.push_back(c);
        added++;
    }
    if (added == 0) {
        throw std::runtime_error(std::string(fn) + ": '" + field + "' : aucun champ numérique à animer");
    }
}

void add_chan(std::vector<Chan>& out, const Value& holder, const Value& key, const Value& cur, const Value& tgt,
              const char* fn) {
    // Copie, PAS une référence : les deux branches du ternaire ont des types différents,
    // donc le résultat est un temporaire — une `const std::string&` serait pendante dès la
    // fin de l'instruction, et les messages d'erreur ci-dessous liraient n'importe quoi.
    std::string field = key.is_string() ? key.as_string() : std::string("(ref)");
    if (cur.is_number() && tgt.is_number()) {
        Chan c;
        c.holder = holder;
        c.key = key;
        c.from = cur.as_num();
        c.to = tgt.as_num();
        c.integral = cur.is_integer() && tgt.is_integer();
        out.push_back(c);
        return;
    }
    if (is_object(cur) && is_object(tgt)) {
        add_struct_chans(out, cur, tgt, field, fn);
        return;
    }
    throw std::runtime_error(std::string(fn) + ": '" + field + "' n'est pas interpolable (" + cur.type_name() +
                             " → " + tgt.type_name() + ") — attendu un nombre ou une instance de classe");
}

// Annule les canaux qui visent déjà (holder, key) : sans cela deux tweens se battraient
// pour le même champ et le résultat dépendrait de l'ordre d'itération. Un tween qui perd
// tous ses canaux est libéré, mais son rappel de fin n'est PAS appelé (il n'a pas fini).
void drop_conflicts(const std::vector<Chan>& chans) {
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (!s_tweens[i].alive)
            continue;
        bool reste = false;
        for (auto& etape : s_tweens[i].etapes) {
            auto& mine = etape.chans;
            for (int c = (int)mine.size() - 1; c >= 0; c--) {
                if (!is_object(mine[c].holder))
                    continue;
                for (const auto& nc : chans) {
                    // Même champ = même objet (identité du Map*) ET même clé (chaînes
                    // internées → comparaison de pointeur suffisante, mais map_get reste
                    // explicite).
                    if (is_object(nc.holder) && mine[c].holder.as_map() == nc.holder.as_map() &&
                        mine[c].key.is_string() && nc.key.is_string() &&
                        mine[c].key.as_string() == nc.key.as_string()) {
                        mine.erase(mine.begin() + c);
                        break;
                    }
                }
            }
            // Une étape d'ATTENTE n'a légitimement aucun canal : elle compte comme du travail
            // restant, sinon écraser un champ annulerait la séquence entière.
            if (!mine.empty() || etape.attente)
                reste = true;
        }
        if (!reste)
            free_tween(i);
    }
}

// Reconnaît les deux derniers arguments par leur TYPE (chaîne/fonction = courbe,
// fonction = rappel de fin), donc aucun ordre imposé — comme ui.slider.
void read_options(const Value* args, int argc, int first, int& curve, Value& curve_fn, Value& on_done,
                  const char* fn) {
    for (int i = first; i < argc; i++) {
        if (args[i].is_string()) {
            curve = curve_index(args[i].as_string(), fn);
        } else if (args[i].is_callable()) {
            if (curve_fn.is_nil() && on_done.is_nil() && i == first) {
                curve_fn = args[i];   // 1re fonction = courbe, 2e = rappel de fin
            } else if (on_done.is_nil()) {
                on_done = args[i];
            } else {
                throw std::runtime_error(std::string(fn) + ": trop de fonctions en argument");
            }
        } else if (!args[i].is_nil()) {
            throw std::runtime_error(std::string(fn) + ": argument " + std::to_string(i + 1) +
                                     " attendu : nom de courbe, fonction, ou nil");
        }
    }
}

double duration_arg(const Value* args, int argc, int i, const char* fn) {
    double d = num_arg(args, argc, i, fn);
    if (!(d > 0.0))
        throw std::runtime_error(std::string(fn) + ": la durée doit être > 0");
    return d;
}

// ── API ─────────────────────────────────────────────────────────────────────────

// tween.to(objet, {champ: cible, …}, durée [, courbe] [, surFin])
int tween_to(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.to: expected objet, {champ: cible}, durée");
    if (!is_object(args[0]))
        throw std::runtime_error("tween.to: le premier argument doit être un objet");
    if (!args[1].is_map())
        throw std::runtime_error("tween.to: le deuxième argument doit être une map {champ: cible}");
    if (args[1].map_size() == 0)
        throw std::runtime_error("tween.to: aucune valeur cible");
    double dur = duration_arg(args, argc, 2, "tween.to");
    int curve = k_curve_default;
    Value curve_fn;
    Value on_done;
    read_options(args, argc, 3, curve, curve_fn, on_done, "tween.to");

    std::vector<Chan> chans;
    for (const auto& kv : args[1].as_map()->data) {
        if (!kv.first.is_string())
            throw std::runtime_error("tween.to: les clés doivent être des noms de champs");
        Value cur = args[0].map_get(kv.first);
        if (cur.is_nil()) {
            throw std::runtime_error("tween.to: le champ '" + kv.first.as_string() + "' est absent de l'objet");
        }
        add_chan(chans, args[0], kv.first, cur, kv.second, "tween.to");
    }
    drop_conflicts(chans);
    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    Etape e;
    e.chans = std::move(chans);
    e.dur = dur;
    e.curve = curve;
    e.curve_fn = curve_fn;
    t.etapes.push_back(std::move(e));
    t.on_done = on_done;
    return ctx.ret(make_handle(slot));
}

// tween.value(ref v, cible, durée [, courbe] [, surFin])
int tween_value(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("tween.value: expected ref variable, cible, durée");
    if (!is_ref(args[0]))
        throw std::runtime_error("tween.value: le premier argument doit être une référence — écrire `ref maVariable`");
    double dur = duration_arg(args, argc, 2, "tween.value");
    int curve = k_curve_default;
    Value curve_fn;
    Value on_done;
    read_options(args, argc, 3, curve, curve_fn, on_done, "tween.value");

    std::vector<Chan> chans;
    Value cur = ref_get(args[0]);
    if (cur.is_number() && args[1].is_number()) {
        Chan c;
        c.ref = args[0];
        c.from = cur.as_num();
        c.to = args[1].as_num();
        c.integral = cur.is_integer() && args[1].is_integer();
        chans.push_back(c);
    } else if (is_object(cur) && is_object(args[1])) {
        add_struct_chans(chans, cur, args[1], "(ref)", "tween.value");
    } else {
        throw std::runtime_error(std::string("tween.value: valeur non interpolable (") + cur.type_name() + " → " +
                                 args[1].type_name() + ")");
    }
    // Deux `ref x` distincts sont deux maps différentes : on ne peut pas reconnaître
    // qu'ils désignent la même variable, donc pas d'écrasement automatique ici (les
    // canaux structurés, qui écrivent dans une instance, sont eux bien dédoublonnés).
    drop_conflicts(chans);
    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    Etape e;
    e.chans = std::move(chans);
    e.dur = dur;
    e.curve = curve;
    e.curve_fn = curve_fn;
    t.etapes.push_back(std::move(e));
    t.on_done = on_done;
    return ctx.ret(make_handle(slot));
}

// tween.sequence(objet, [ {to: {champ: cible}, delay: secondes [, curve: nom] [, target: objet]}, … ])
//
// Une SUITE d'étapes jouées l'une après l'autre. La clé de temps est `delay` dans les deux
// rôles : durée de l'animation quand l'étape porte `to`, simple attente sinon — une seule clé
// de temps, dont le sens se lit à la présence de `to`.
//
// Toute clé inconnue est REFUSÉE avec la liste des clés admises : sans ce refus, un
// `duration` ou un `easing` mal choisi serait ignoré en silence et l'étape partirait sans
// durée. C'est la faute qu'on cherche le plus longtemps.
int tween_sequence(CallCtx& ctx) {
    static constexpr const char* FN = "tween.sequence";
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 2)
        throw std::runtime_error(std::string(FN) + ": expected objet, [étapes]");
    if (!is_object(args[0]))
        throw std::runtime_error(std::string(FN) + ": le premier argument doit être un objet");
    if (!args[1].is_array())
        throw std::runtime_error(std::string(FN) + ": le deuxième argument doit être un tableau d'étapes");
    int64_t nb = args[1].array_size();
    if (nb == 0)
        throw std::runtime_error(std::string(FN) + ": la séquence est vide");

    // Après la liste, un SEUL argument est admis : le rappel de fin. On ne passe pas par
    // read_options, qui prendrait une chaîne pour une courbe — or la courbe se déclare par
    // étape, et une chaîne nommant la courbe par défaut y était acceptée sans effet.
    Value on_done;
    for (int i = 2; i < argc; i++) {
        if (args[i].is_nil())
            continue;
        if (args[i].is_string())
            throw std::runtime_error(std::string(FN) + ": la courbe se déclare par étape (clé `curve`)");
        if (!args[i].is_callable())
            throw std::runtime_error(std::string(FN) + ": argument " + std::to_string(i + 1) +
                                     " attendu : fonction de rappel de fin, ou nil");
        if (!on_done.is_nil())
            throw std::runtime_error(std::string(FN) + ": un seul rappel de fin");
        on_done = args[i];
    }

    std::vector<Etape> etapes;
    for (int64_t k = 1; k <= nb; k++) {   // tableaux Ollin : indexés à 1
        Value brut = args[1].array_get(k);
        const std::string ou = std::string(FN) + ": étape " + std::to_string(k);
        if (!brut.is_map())
            throw std::runtime_error(ou + " doit être une map {to: …, delay: …}");
        Value cible = args[0], vers, courbe;
        double delai = -1.0;
        for (const auto& kv : brut.as_map()->data) {
            if (!kv.first.is_string())
                throw std::runtime_error(ou + " : les clés doivent être des noms");
            const std::string& cle = kv.first.as_string();
            if (cle == "to") {
                vers = kv.second;
            } else if (cle == "delay") {
                if (!kv.second.is_number())
                    throw std::runtime_error(ou + " : `delay` doit être un nombre de secondes");
                delai = kv.second.as_num();
            } else if (cle == "curve") {
                courbe = kv.second;
            } else if (cle == "target") {
                cible = kv.second;
            } else {
                throw std::runtime_error(ou + " : clé inconnue '" + cle + "' — admises : to, delay, curve, target");
            }
        }
        if (!(delai > 0.0))
            throw std::runtime_error(ou + " : `delay` manquant ou <= 0");
        Etape e;
        e.dur = delai;
        if (!courbe.is_nil()) {
            if (courbe.is_string())
                e.curve = curve_index(courbe.as_string(), FN);
            else if (courbe.is_callable())
                e.curve_fn = courbe;
            else
                throw std::runtime_error(ou + " : `curve` doit être un nom de courbe ou une fonction");
        }
        e.attente = vers.is_nil();
        if (!vers.is_nil()) {
            if (!is_object(cible))
                throw std::runtime_error(ou + " : `target` doit être un objet");
            if (!vers.is_map() || vers.map_size() == 0)
                throw std::runtime_error(ou + " : `to` doit être une map {champ: cible} non vide");
            for (const auto& kv : vers.as_map()->data) {
                if (!kv.first.is_string())
                    throw std::runtime_error(ou + " : les champs de `to` doivent être des noms");
                Value cur = cible.map_get(kv.first);
                if (cur.is_nil())
                    throw std::runtime_error(ou + " : le champ '" + kv.first.as_string() + "' est absent de l'objet");
                add_chan(e.chans, cible, kv.first, cur, kv.second, FN);
            }
            drop_conflicts(e.chans);
        }
        etapes.push_back(std::move(e));
    }

    int slot = alloc_tween();
    Tw& t = s_tweens[slot];
    t.etapes = std::move(etapes);
    t.on_done = on_done;
    return ctx.ret(make_handle(slot));
}

int tween_cancel_all(CallCtx& ctx) {
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (s_tweens[i].alive)
            free_tween(i);
    }
    return ctx.ret(Value{});
}

int tween_count(CallCtx& ctx) {
    int64_t n = 0;
    for (const auto& t : s_tweens) {
        if (t.alive)
            n++;
    }
    return ctx.ret(Value(n));
}

int tween_curves(CallCtx& ctx) {
    Value a = Value::make_array();
    for (const auto& c : k_curves)
        a.array_push(Value(std::string(c.name)));
    return ctx.ret(a);
}

// tween.update(dt) — pilotage manuel, pour un programme SANS boucle graphique (tests,
// natif headless). No-op dès que le moteur avance les tweens lui-même, sinon un appel
// laissé dans draw() doublerait la vitesse.
int tween_update(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    double dt = num_arg(args, argc, 0, "tween.update");
    if (!s_engine_driven)
        advance(dt);
    return ctx.ret(Value{});
}

// ── Méthodes du handle ──────────────────────────────────────────────────────────

// CALL_METHOD injecte le receveur en args[0] pour une instance : les arguments
// utilisateur commencent donc à args[1], comme dans ui_module.
int method_pause(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.pause");
    if (slot >= 0)
        s_tweens[slot].paused = true;
    return ctx.ret(ctx.args[0]);
}

int method_resume(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.resume");
    if (slot >= 0)
        s_tweens[slot].paused = false;
    return ctx.ret(ctx.args[0]);
}

int method_cancel(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.cancel");
    if (slot >= 0)
        free_tween(slot);
    return ctx.ret(ctx.args[0]);
}

int method_is_done(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.isDone");
    return ctx.ret(Value::make_bool(slot < 0));
}

int method_progress(CallCtx& ctx) {
    int slot = handle_slot(ctx.args[0], "tween.progress");
    if (slot < 0)
        return ctx.ret(Value(1.0));
    const Tw& t = s_tweens[slot];
    // Avancement sur le PLAN entier, en TEMPS : les étapes d'une séquence n'ont pas la même
    // durée, donc compter les étapes franchies donnerait une progression qui saute. Le
    // dernier segment dépasse sa durée en attendant la passe qui terminera le tween, d'où le
    // plafond avant la division ; ensuite (base + p) / total ≤ 1 par construction, et seul le
    // plancher reste à poser (délai, temps négatif). Un plan sans fin rend l'avancement de
    // son tour courant.
    double cycle = duree_cycle(t);
    double fait = 0.0;
    for (size_t k = 0; k < t.pos && k < t.etapes.size(); k++)
        fait += t.etapes[etape_index(t, k)].dur;
    double p = cycle > 0.0 ? std::min((fait + t.elapsed) / cycle, 1.0) : 1.0;
    double total = t.endless ? 1.0 : (double)t.plan.size();
    double base = t.endless ? 0.0 : (double)t.seg;
    p = (base + p) / total;
    return ctx.ret(Value(p < 0.0 ? 0.0 : p));
}

// UNE seule méthode pour toutes les répétitions : `repeat([occurrences] [, allerRetour])`.
//
//   .repeat()             aller, aller, …                 sans fin
//   .repeat(2)            aller, aller
//   .repeat(2, true)      aller, aller, retour, retour    (le retour porte sur l'ENSEMBLE)
//   .repeat(nil, true)    aller, retour, aller, retour, … sans fin
//
// Le compte est reconnu par sa POSITION et non par son type : `true` vaut 1 en Ollin (il n'y
// a pas de type booléen), donc `repeat(true)` serait indistinguable de `repeat(1)`. D'où le
// `nil` explicite pour dire « pas de compte » tout en demandant l'aller-retour.
//
// L'aller-retour ajoute au plan son miroir : le vecteur renversé, sens inversés. Deux appels
// successifs composent donc, chacun agissant sur le plan construit jusque-là.
int method_repeat(CallCtx& ctx) {
    static constexpr const char* FN = "tween.repeat";
    double n = 0.0;   // 0 = aucun compte fourni ⇒ sans fin
    if (ctx.argc > 1 && !ctx.args[1].is_nil()) {
        if (!ctx.args[1].is_number())
            throw std::runtime_error(std::string(FN) + ": le nombre d'occurrences doit être un nombre ou nil");
        n = ctx.args[1].as_num();
        if (n < 1.0 || n != std::floor(n))
            throw std::runtime_error(std::string(FN) + ": le nombre d'occurrences doit être un entier >= 1");
    }
    bool aller_retour = ctx.argc > 2 && !is_falsy(ctx.args[2]);
    int slot = handle_slot(ctx.args[0], FN);
    if (slot >= 0) {
        Tw& t = s_tweens[slot];
        std::vector<int8_t> bloc = t.plan;
        for (int k = 1; k < (int)n; k++)
            t.plan.insert(t.plan.end(), bloc.begin(), bloc.end());
        if (aller_retour) {
            for (size_t i = t.plan.size(); i > 0; i--)
                t.plan.push_back((int8_t)-t.plan[i - 1]);
        }
        t.endless = (n == 0.0);
    }
    return ctx.ret(ctx.args[0]);
}

// Retarde le DÉMARRAGE : la valeur de départ est lue au premier avancement réel, donc
// après le délai — un tween retardé part de la valeur qu'aura la variable à ce moment.
int method_delay(CallCtx& ctx) {
    double d = num_arg(ctx.args, ctx.argc, 1, "tween.delay");
    if (d < 0.0)
        throw std::runtime_error("tween.delay: le délai doit être >= 0");
    int slot = handle_slot(ctx.args[0], "tween.delay");
    if (slot >= 0)
        s_tweens[slot].delay = d;
    return ctx.ret(ctx.args[0]);
}

Value make_tween_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Tween")));
    cls.map_set(Value(std::string("pause")), Value::make_builtin(method_pause));
    cls.map_set(Value(std::string("resume")), Value::make_builtin(method_resume));
    cls.map_set(Value(std::string("cancel")), Value::make_builtin(method_cancel));
    cls.map_set(Value(std::string("isDone")), Value::make_builtin(method_is_done));
    cls.map_set(Value(std::string("progress")), Value::make_builtin(method_progress));
    cls.map_set(Value(std::string("delay")), Value::make_builtin(method_delay));
    cls.map_set(Value(std::string("repeat")), Value::make_builtin(method_repeat));
    return cls;
}

Value tween_class() {
    static Value cls = make_tween_class();
    return cls;
}

// ── Avancement ──────────────────────────────────────────────────────────────────

// Prend la courbe PAR VALEUR (copie de la Value) et non une référence sur le tween : une
// courbe fournie par le script peut déclarer un tween, donc réallouer s_tweens, et toute
// référence sur un élément serait alors pendante.
double eased(Value curve_fn, int curve, double p) {
    if (curve_fn.is_callable()) {
        Value r = VM::current()->call_value(curve_fn, Value(p));
        return r.is_number() ? r.as_num() : p;
    }
    return k_curves[curve].fn(p);
}

void write_chan(const Chan& c, double v) {
    Value out = c.integral ? Value((int64_t)std::llround(v)) : Value(v);
    if (c.ref.is_map()) {
        ref_set(c.ref, out);
        return;
    }
    Value holder = c.holder;   // map_set mute la map : une copie de la Value suffit (même Map*)
    holder.map_set(c.key, out);
}

// Lit les valeurs de départ d'une étape, une seule fois : elle part de ce que l'étape
// précédente a laissé. Aux passages suivants (répétition, marche arrière) les bornes sont
// conservées, sinon un retour ne va nulle part.
void demarrer_etape(Tw& t, size_t idx) {
    if (t.etapes[idx].demarree)
        return;
    t.etapes[idx].demarree = true;
    for (auto& c : t.etapes[idx].chans) {
        Value cur = c.ref.is_map() ? ref_get(c.ref) : c.holder.map_get(c.key);
        if (cur.is_number())
            c.from = cur.as_num();
    }
}

// Pose les canaux d'une étape à l'extrémité qu'elle vise, dans le sens du segment courant.
// Appelée quand l'étape est franchie en un seul pas de temps : sans elle, une étape plus
// courte que le pas ne laisserait aucune trace.
void poser_fin_etape(Tw& t, size_t pos) {
    int8_t sens = t.plan[t.seg];
    std::vector<Chan> chans = t.etapes[etape_index(t, pos)].chans;
    for (const auto& c : chans)
        write_chan(c, sens > 0 ? c.to : c.from);
}

void advance(double dt) {
    if (dt <= 0.0 || s_tweens.empty())
        return;
    s_pass++;
    // Rappels de fin COLLECTÉS puis appelés après la passe : un rappel peut créer ou
    // annuler des tweens, donc faire push_back sur s_tweens pendant qu'on l'itère.
    std::vector<Value> finished;
    for (int i = 0; i < (int)s_tweens.size(); i++) {
        if (!s_tweens[i].alive || s_tweens[i].paused || s_tweens[i].born_pass == s_pass)
            continue;
        double step = dt;
        {
            Tw& t = s_tweens[i];
            if (t.delay > 0.0) {
                t.delay -= step;
                if (t.delay > 0.0)
                    continue;
                step = -t.delay;   // le reliquat du pas sert à l'animation
                t.delay = 0.0;
            }
            t.elapsed += step;
        }
        // Fin d'une ÉTAPE : on passe à la suivante en gardant le reliquat de temps, sinon une
        // animation courte perdrait une fraction de seconde à chaque parcours. Quand la suite
        // est épuisée, le segment de plan suivant la rejoue (en sens inverse si -1).
        double p = 1.0;
        bool ends = true;      // dernier segment terminé → le tween a fini
        bool seg_ends = true;  // étape courante terminée
        int8_t sens = 1;
        size_t idx = 0;
        // Cette boucle appelle du code Ollin (getter d'une `ref` dans demarrer_etape, setter
        // dans poser_fin_etape). Ce code peut déclarer un tween, donc faire push_back sur
        // s_tweens et RÉALLOUER le vecteur : aucune référence `Tw&` ne doit traverser ces
        // appels, et la vitalité du slot est revérifiée après chacun.
        {
            while (true) {
                if (!s_tweens[i].alive)
                    break;
                Tw& t = s_tweens[i];
                double dur = t.etapes[etape_index(t, t.pos)].dur;
                if (dur <= 0.0 || t.elapsed < dur)
                    break;
                // Dernière étape du dernier segment : on sort SANS soustraire, en gardant
                // elapsed >= dur. C'est ce dépassement qui dit « terminé » plus bas — le
                // soustraire ferait croire au tween qu'il redémarre cette étape, et il
                // réécrivait alors la valeur de DÉPART au lieu de la cible (constaté).
                if (t.pos + 1 >= t.etapes.size() && t.seg + 1 >= t.plan.size() && !t.endless)
                    break;
                size_t franchie = etape_index(t, t.pos);
                // L'étape franchie est DÉMARRÉE puis POSÉE à son extrémité exacte avant qu'on
                // la quitte : sinon une étape plus courte qu'un pas de temps serait sautée
                // sans jamais lire ses bornes ni écrire sa cible.
                demarrer_etape(t, franchie);          // ← peut exécuter un getter Ollin
                poser_fin_etape(t, t.pos);            // ← peut exécuter un setter Ollin
                if (!s_tweens[i].alive)
                    break;   // le code appelé a annulé ce tween
                Tw& t2 = s_tweens[i];                 // référence RELUE après les appels
                t2.elapsed -= t2.etapes[franchie].dur;
                if (t2.pos + 1 < t2.etapes.size()) {
                    t2.pos++;
                } else if (t2.seg + 1 < t2.plan.size()) {
                    t2.seg++;
                    t2.pos = 0;
                } else {
                    t2.seg = 0;   // sans fin : on rejoue le plan depuis son premier segment
                    t2.pos = 0;
                }
            }
            if (!s_tweens[i].alive)
                continue;   // annulé en cours de franchissement : plus rien à écrire
            Tw& t = s_tweens[i];
            sens = t.plan[t.seg];
            idx = etape_index(t, t.pos);
            double dur = t.etapes[idx].dur;
            if (t.elapsed < dur) {
                p = dur > 0.0 ? t.elapsed / dur : 1.0;
                seg_ends = false;
                ends = false;
            }
        }
        demarrer_etape(s_tweens[i], idx);   // hors de toute référence retenue
        if (!s_tweens[i].alive)
            continue;
        // Écritures et rappel de courbe : ils exécutent du code Ollin (setter d'une `ref`,
        // courbe personnalisée), donc plus aucune référence à s_tweens ne doit survivre.
        {
            std::vector<Chan> chans = s_tweens[i].etapes[idx].chans;
            Value curve_fn = s_tweens[i].etapes[idx].curve_fn;
            int curve = s_tweens[i].etapes[idx].curve;
            double f = seg_ends ? 1.0 : eased(curve_fn, curve, p);
            for (const auto& c : chans) {
                // Un segment de sens -1 se joue de la cible vers le départ. À la fin d'une
                // étape on pose la valeur EXACTE de son extrémité : une courbe à dépassement
                // (back, elastic) ne rend pas 1 en 1, et un arrondi laisserait 0,999.
                double a = sens > 0 ? c.from : c.to;
                double b = sens > 0 ? c.to : c.from;
                write_chan(c, seg_ends ? b : a + (b - a) * f);
            }
        }
        if (ends && tween_alive(i, s_tweens[i].gen)) {
            Value cb = s_tweens[i].on_done;
            free_tween(i);
            if (cb.is_callable())
                finished.push_back(cb);
        }
    }
    for (auto& cb : finished)
        VM::current()->call_value(cb);
}

} // namespace

void tween_update_all(double dt) {
    s_engine_driven = true;   // le moteur pilote → tween.update côté script devient no-op
    advance(dt);
}

void tween_reset() {
    s_tweens.clear();
    s_free.clear();
    s_engine_driven = false;
    s_pass = 0;
}

Value make_tween_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("to")), Value::make_builtin(tween_to));
    m.map_set(Value(std::string("sequence")), Value::make_builtin(tween_sequence));
    m.map_set(Value(std::string("value")), Value::make_builtin(tween_value));
    m.map_set(Value(std::string("update")), Value::make_builtin(tween_update));
    m.map_set(Value(std::string("cancelAll")), Value::make_builtin(tween_cancel_all));
    m.map_set(Value(std::string("count")), Value::make_builtin(tween_count));
    m.map_set(Value(std::string("curves")), Value::make_builtin(tween_curves));
    return m;
}
