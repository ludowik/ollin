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

// Called at the start of each ollin_run() to release stale GL handles
void image_reset();

// Called by graphics.sprite() — draws image id at (x,y) scaled to (dw,dh).
// Pass dw=0/dh=0 to use the image's natural size.
// tint is RGBA 0-255 components.
void image_draw_sprite(int id, float x, float y, float dw, float dh, unsigned char r, unsigned char g, unsigned char b,
                       unsigned char a);
