#pragma once
#include "chunk.h"
#include <cstdint>
#include <string>
#include <vector>

Value make_image_module();

// WASM interop: preload raw bytes under a name so image.load(name) works
void image_preload(const std::string& name, const std::vector<uint8_t>& bytes,
                   const std::string& ext); // ext with dot, e.g. ".png"

// Convenience: decode base64 then preload. ext without dot, e.g. "png".
void image_preload_b64(const std::string& name, const std::string& b64, const std::string& ext);

// Shared base64 codec: the decoder preloads every kind of resource (images, 3D models), the
// encoder hands a screenshot to the JS host — a raw binary string would be re-encoded as UTF-8 by
// embind, and thus corrupted.
std::vector<uint8_t> image_b64_decode(const std::string& b64);
std::string image_b64_encode(const uint8_t* data, size_t len);

// Called at the start of each ollin_run() to release stale GL handles
void image_reset();

// GL texture id of an image handle, or 0 when not found. Used by the 3D side
// (graphics.texture) to texture meshes with an image from this module.
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

// Global tint (graphics.tint / noTint), applied by default to image.draw and graphics.sprite.
// RGBA in 0-255; has=false means no tint, that is white.
void image_set_tint(bool has, unsigned char r, unsigned char g, unsigned char b, unsigned char a);
void image_get_tint(bool* has, unsigned char* r, unsigned char* g, unsigned char* b, unsigned char* a);

// Global image anchoring (graphics.spriteMode): x,y is either the top-left corner or the centre.
// Like the tint, the state lives here because it applies to BOTH surfaces that draw an image,
// graphics.sprite and image.draw.
enum { SPRITE_CORNER = 0, SPRITE_CENTER = 1 };
void image_set_sprite_mode(int mode);
int image_get_sprite_mode();
