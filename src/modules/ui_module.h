#pragma once
#include "chunk.h"
#include "modules/module_utils.h"
#include <stdexcept>

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

inline void ui_check_menu_args(const Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("ui.menu: expected label");
    if (!args[0].is_string())
        throw std::runtime_error("ui.menu: label must be a string");
}
