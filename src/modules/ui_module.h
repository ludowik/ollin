#pragma once
#include "chunk.h"
#include "modules/module_utils.h"
#include "vm.h"
#include <algorithm>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

Value make_ui_module();

// Appelés par la boucle de rendu (graphics_module.cpp) :
// ui_poll()  AVANT mouse_poll — renvoie true si un widget a pris le clic, auquel cas
//            le clic ne doit PAS être transmis aux callbacks mouse.* du script.
// ui_draw()  APRÈS draw() — dessine la pile de widgets par-dessus la scène.
// ui_reset() au démarrage d'un PROGRAMME (ollin_run, wasm_main.cpp) — PAS dans
//            gfx_run : les widgets sont déclarés au niveau du fichier, donc AVANT
//            graphics.run, et un reset là les effacerait tous. Nécessaire car les
//            statiques survivent au VM entre deux exécutions du playground.
bool ui_poll();
void ui_draw();
void ui_reset();

// ── Validation des arguments, PARTAGÉE par le module et le stub ──────────────────
// Une faute d'appel doit être signalée même sans raylib (le binaire de test utilise
// le stub) : un seul endroit pour les messages, aucune divergence possible.
// `args`/`argc` désignent les arguments UTILISATEUR : sur un appel de méthode, le
// receveur (self) a déjà été retiré par l'appelant.
inline void ui_check_button_args(const Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("ui.button: expected label, function");
    if (!args[0].is_string())
        throw std::runtime_error("ui.button: label must be a string");
    if (!args[1].is_callable())
        throw std::runtime_error("ui.button: second argument must be a function");
}

inline void ui_check_checkbox_args(const Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("ui.checkbox: expected label, ref variable");
    if (!args[0].is_string())
        throw std::runtime_error("ui.checkbox: label must be a string");
    if (!is_ref(args[1]))
        throw std::runtime_error("ui.checkbox: second argument must be a reference — write `ref maVariable`");
    if (argc > 2 && !args[2].is_nil() && !args[2].is_callable())
        throw std::runtime_error("ui.checkbox: third argument must be a function");
}

// ui.slider(libellé, ref v, min, max [, défaut] [, surChange]) — les deux derniers
// arguments sont reconnus par leur TYPE : un nombre est la valeur par défaut, une
// fonction le rappel de changement. Aucun ordre imposé, donc aucune ambiguïté.
inline void ui_check_slider_args(const Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("ui.slider: expected label, ref variable, min, max");
    if (!args[0].is_string())
        throw std::runtime_error("ui.slider: label must be a string");
    if (!is_ref(args[1]))
        throw std::runtime_error("ui.slider: second argument must be a reference — write `ref maVariable`");
    if (!args[2].is_number() || !args[3].is_number())
        throw std::runtime_error("ui.slider: min and max must be numbers");
    if (args[2].as_num() >= args[3].as_num())
        throw std::runtime_error("ui.slider: min must be smaller than max");
    for (int i = 4; i < argc; ++i) {
        if (!args[i].is_nil() && !args[i].is_number() && !args[i].is_callable())
            throw std::runtime_error("ui.slider: extra argument must be a number (default) or a function");
    }
}

// Valeur par défaut d'un slider : le premier argument numérique après max, sinon min.
inline Value ui_slider_default(const Value* args, int argc) {
    for (int i = 4; i < argc; ++i) {
        if (args[i].is_number())
            return args[i];
    }
    return args[2];
}

// Une variable liée qui vaut nil est INITIALISÉE à la déclaration : le script peut la
// lire dès la première frame. Partagé avec le stub, qui n'a pas de rendu mais doit
// donner la même valeur au script.
inline void ui_slider_init(const Value* args, int argc) {
    if (ref_get(args[1]).is_nil())
        ref_set(args[1], ui_slider_default(args, argc));
}

// Éléments d'une liste : le LIBELLÉ affiché et la VALEUR renvoyée. Un tableau donne ses
// valeurs, une map (ou un enum) ses clés — la même règle que `for … in`, dont la variable
// unique reçoit la valeur d'un tableau et la clé d'une map.
//
// L'ORDRE est figé ici, car une map n'en a pas : un enum est trié par valeur, ce qui
// restitue l'ordre de déclaration, une map ordinaire par libellé, faute de mieux. Sans
// cela la liste se réordonnerait d'une ouverture à l'autre.
inline std::vector<std::pair<std::string, Value>> ui_list_items(const Value& source) {
    std::vector<std::pair<std::string, Value>> out;
    if (source.is_array()) {
        int64_t n = source.array_size();
        for (int64_t i = 1; i <= n; i++) {
            Value v = source.array_get(i);
            out.push_back({value_to_string(v), v});
        }
        return out;
    }
    // Clés collectées AVANT tout libellé : value_to_string peut appeler la méta-méthode
    // `__str` d'une clé, donc du code Ollin, qui muterait la map et invaliderait
    // l'itérateur en pleine boucle.
    bool by_value = source.as_map()->kind == Map::ENUM;
    std::vector<Value> keys;
    for (const auto& kv : source.as_map()->data) {
        if (!kv.second.is_number())
            by_value = false;
        keys.push_back(kv.first);
    }
    for (const auto& k : keys)
        out.push_back({value_to_string(k), k});
    if (by_value) {
        std::sort(out.begin(), out.end(), [&](const auto& a, const auto& b) {
            return source.map_get(a.second).as_num() < source.map_get(b.second).as_num();
        });
    } else {
        std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
            return a.first < b.first;
        });
    }
    return out;
}

inline void ui_check_list_args(const Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("ui.list: expected label, tableau|map|enum, ref variable");
    if (!args[0].is_string())
        throw std::runtime_error("ui.list: label must be a string");
    if (!args[1].is_array() && !args[1].is_map())
        throw std::runtime_error("ui.list: second argument must be an array, a map or an enum");
    if (args[1].is_array() ? args[1].array_size() == 0 : args[1].map_size() == 0)
        throw std::runtime_error("ui.list: the list is empty");
    if (!is_ref(args[2]))
        throw std::runtime_error("ui.list: third argument must be a reference — write `ref maVariable`");
    if (argc > 3 && !args[3].is_nil() && !args[3].is_callable())
        throw std::runtime_error("ui.list: fourth argument must be a function");
}

// Une liste est en MONO-sélection : il y a toujours un élément retenu. Une variable liée
// à nil est donc initialisée au premier élément, comme un slider prend son défaut.
inline void ui_list_init(const Value* args) {
    if (!ref_get(args[2]).is_nil())
        return;
    auto items = ui_list_items(args[1]);
    if (!items.empty())
        ref_set(args[2], items[0].second);
}

inline void ui_check_menu_args(const Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("ui.menu: expected label");
    if (!args[0].is_string())
        throw std::runtime_error("ui.menu: label must be a string");
}
