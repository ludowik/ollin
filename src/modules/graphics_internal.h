#pragma once
// Frontière interne entre les deux unités de compilation du module graphics :
//   graphics_module.cpp  — 2D, fenêtre/boucle de rendu, styles, transforms, registre
//   graphics3d.cpp       — 3D (caméra, éclairage, batcher instancié, primitives 3D)
// On n'expose PAS les statiques en vrac : des accesseurs pour l'état de style
// (défini côté 2D, lu côté 3D) et des ponts de fonctions inter-fichiers.
#include "value.h"
#include <raylib.h>

// ── Helpers partagés ────────────────────────────────────────────────────────
inline int gfx_to_int(const Value& v) {
    if (v.is_integer())
        return (int)v.as_int();
    if (v.is_float())
        return (int)v.as_float();
    return 0;
}
// Même permissivité que gfx_to_int (0 si ce n'est pas un nombre), mais sans
// troncature : pour calculer avant d'arrondir, p. ex. un décalage d'une demi-taille.
inline double gfx_to_num(const Value& v) {
    if (v.is_integer())
        return (double)v.as_int();
    if (v.is_float())
        return v.as_float();
    return 0.0;
}
// Value (objet Color / classe) → Color raylib ; lève si ce n'en est pas un.
Color gfx_to_color(const Value& v);

// ── Zone de tracé en unités LOGIQUES (défini par graphics.canvas) ───────────────
// La projection d'une frame est en unités logiques : un module qui dessine dedans
// (ui_module) doit s'y référer, pas à GetScreenWidth() qui est en pixels physiques.
int gfx_logical_width();
int gfx_logical_height();
// Bande occupée en haut par l'overlay FPS (composé PAR-DESSUS la render texture) :
// un module qui dessine en haut de la zone doit la laisser libre.
int gfx_overlay_height();

// ── État de style courant (défini dans graphics_module.cpp, lu par graphics3d.cpp) ──
bool gfx_has_fill();
Color gfx_fill_color();
bool gfx_has_stroke();
Color gfx_stroke_color();
float gfx_stroke_size();
int gfx_segments();

// ── Invalidation du cache mesh 3D (défini dans graphics3d.cpp) ───────────────
void reset3d_shape_cache();

// ── Ponts 2D → 3D (définis dans graphics3d.cpp) ─────────────────────────────
void end3d_internal();          // flush des buckets + EndMode3D (no-op hors bloc 3D)
void reset3d_lighting_state();   // remet l'éclairage 3D à l'état par défaut
void reset3d_graphics_state();   // libère les ressources GL 3D (avant destruction du contexte)
void reset3d_frame_state();      // remet la texture 3D courante (appelé chaque frame par resetStyles)
void register3d_graphics(Value& m);   // enregistre les builtins 3D dans le module graphics

// ── Texture 3D courante (état de style, sauvé/restauré par push/pushStyle) ──
unsigned int gfx3d_get_texture();      // id GL de la texture 3D courante (0 = blanche)
void gfx3d_set_texture(unsigned int id);

// ── Modèles externes : préchargement des octets (chargement GPU différé) ────
#include <string>
#include <vector>
void model_preload_bytes(const std::string& name, std::vector<unsigned char> bytes, const std::string& ext);
