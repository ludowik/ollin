#pragma once
#include "chunk.h"
#include <cstdint>
#include <string>
#include <vector>

Value makeImageModule();

// WASM interop: preload raw bytes under a name so image.load(name) works
void image_preload(const std::string& name, const std::vector<uint8_t>& bytes,
                   const std::string& ext); // ext with dot, e.g. ".png"

// Convenience: decode base64 then preload. ext without dot, e.g. "png".
void image_preload_b64(const std::string& name, const std::string& b64, const std::string& ext);

// Décodeur base64 partagé (réutilisé pour précharger d'autres ressources, ex. modèles 3D).
std::vector<uint8_t> image_b64_decode(const std::string& b64);

// Called at the start of each ollin_run() to release stale GL handles
void image_reset();

// Renvoie l'id GL de texture d'un handle image (0 si introuvable) — utilisé par
// la 3D (graphics.texture) pour texturer les meshes avec une image du module.
unsigned int image_gl_texid(int id);

// Called by graphics.sprite() — draws image id at (x,y) scaled to (dw,dh).
// Pass dw=0/dh=0 to use the image's natural size.
// tint is RGBA 0-255 components.
void image_draw_sprite(int id, float x, float y, float dw, float dh, unsigned char r, unsigned char g, unsigned char b,
                       unsigned char a);

// Streaming texture API (camera module).
// Creates a plain Texture2D from blank RGBA data. Returns a handle map {id,width,height}.
// *id_out receives the numeric id for image_push_pixels.
Value image_alloc_tex(int w, int h, int* id_out);
// Pushes raw RGBA8 pixels to a streaming texture. No-op if id is invalid.
void  image_push_pixels(int id, const uint8_t* rgba);
// Returns true if the texture id is still alive (not cleared by image_reset).
bool  image_tex_valid(int id);
// Frees a streaming texture (GPU + CPU shadow) by id. No-op if invalid.
void  image_free_tex(int id);

// Teinte globale (graphics.tint / noTint) : appliquée par défaut à image.draw et
// graphics.sprite. RGBA 0-255. `has`=false → pas de teinte (blanc).
void image_set_tint(bool has, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
void image_get_tint(bool* has, unsigned char* r, unsigned char* g, unsigned char* b, unsigned char* a);
