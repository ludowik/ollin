#pragma once
// Frontière interne entre les deux unités de compilation du module graphics :
//   graphics_module.cpp  — 2D, fenêtre/boucle de rendu, styles, transforms, registre
//   graphics3d.cpp       — 3D (caméra, éclairage, batcher instancié, primitives 3D)
// On n'expose PAS les statiques en vrac : des accesseurs pour l'état de style
// (défini côté 2D, lu côté 3D) et des ponts de fonctions inter-fichiers.
#include "value.h"
#include <raylib.h>

// ── Helpers partagés ────────────────────────────────────────────────────────
inline int gfxToInt(const Value& v) {
    if (v.isInteger())
        return (int)v.asInt();
    if (v.isFloat())
        return (int)v.asFloat();
    return 0;
}
// Value (objet Color / classe) → Color raylib ; lève si ce n'en est pas un.
Color gfxToColor(const Value& v);

// ── État de style courant (défini dans graphics_module.cpp, lu par graphics3d.cpp) ──
bool gfxHasFill();
Color gfxFillColor();
bool gfxHasStroke();
Color gfxStrokeColor();
float gfxStrokeSize();
int gfxSegments();

// ── Invalidation du cache mesh 3D (défini dans graphics3d.cpp) ───────────────
void reset3dShapeCache();

// ── Ponts 2D → 3D (définis dans graphics3d.cpp) ─────────────────────────────
void end3dInternal();          // flush des buckets + EndMode3D (no-op hors bloc 3D)
void reset3dLightingState();   // remet l'éclairage 3D à l'état par défaut
void reset3dGraphicsState();   // libère les ressources GL 3D (avant destruction du contexte)
void reset3dFrameState();      // remet la texture 3D courante (appelé chaque frame par resetStyles)
void register3dGraphics(Value& m);   // enregistre les builtins 3D dans le module graphics

// ── Texture 3D courante (état de style, sauvé/restauré par push/pushStyle) ──
unsigned int gfx3dGetTexture();      // id GL de la texture 3D courante (0 = blanche)
void gfx3dSetTexture(unsigned int id);

// ── Modèles externes : préchargement des octets (chargement GPU différé) ────
#include <string>
#include <vector>
void model_preload_bytes(const std::string& name, std::vector<unsigned char> bytes, const std::string& ext);
