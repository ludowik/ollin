#pragma once
#include <raylib.h>

// ── Polices du moteur ───────────────────────────────────────────────────────────
// Registre de polices EMBARQUÉES, désignées par un nom : aucun fichier à trouver à
// l'exécution, donc le même rendu sur toutes les cibles (WASM compris). Les atlas
// sont générés par tools/gen_ui_font.cpp (ExportFontAsCode de raylib).
//
// Partagé par `graphics` (police courante des appels à text) et par `ui` (libellés
// des widgets), pour que l'atlas ne soit chargé qu'une fois.

int engine_font_count();
const char* engine_font_name(int idx);
// -1 si le nom est inconnu (l'appelant décide du message d'erreur).
int engine_font_index(const char* name);
// La police est chargée au PREMIER usage : construire son atlas crée une texture,
// donc exige un contexte graphique. Repli sur GetFontDefault() en cas d'échec.
Font engine_font(int idx);
// Oublie les polices SANS les décharger : leurs textures appartiennent au contexte
// du programme précédent, déjà détruit. Appelé au démarrage d'un programme.
void engine_font_reset();

// Index de la police par défaut (celle du registre nommée "sans").
int engine_font_default();
