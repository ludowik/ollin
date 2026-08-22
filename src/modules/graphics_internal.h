#pragma once
// Internal boundary between the two translation units of the graphics module:
//   graphics_module.cpp  2D, window and render loop, styles, transforms, registry
//   graphics3d.cpp       3D: camera, lighting, instanced batcher, 3D primitives
// The statics are NOT exposed wholesale: what crosses is a set of accessors for the style state
// (defined on the 2D side, read on the 3D side) and a few function bridges between the files.
#include "value.h"
#include <raylib.h>
#include <string>

inline int gfx_to_int(const Value& v) {
    if (v.is_integer())
        return (int)v.as_int();
    if (v.is_float())
        return (int)v.as_float();
    return 0;
}
// As permissive as gfx_to_int — 0 when the value is not a number — but without truncating, for
// computing before rounding, such as an offset of half a size.
inline double gfx_to_num(const Value& v) {
    if (v.is_integer())
        return (double)v.as_int();
    if (v.is_float())
        return v.as_float();
    return 0.0;
}
// A Value (a Color instance or class) to a raylib Color; throws when it is neither.
Color gfx_to_color(const Value& v);

// Screenshot requested by the HOST (the playground's fullscreen mode).
// Deferred to the end of the frame like graphics.screenshot: that is the only moment when the
// default framebuffer holds the composed screen. gfx_take_capture returns the PNG as base64 and
// clears it; an empty string means it is not ready yet.
void gfx_request_capture();
std::string gfx_take_capture();

// Drawing area in LOGICAL units, as set by graphics.canvas.
// A frame's projection is in logical units, so a module drawing inside it (ui_module) must refer to
// these rather than to GetScreenWidth(), which is in physical pixels.
int gfx_logical_width();
int gfx_logical_height();
// Strip taken at the top by the FPS overlay, composed ON TOP OF the render texture: a module
// drawing at the top of the area must leave it free.

// Current style state: defined in graphics_module.cpp, read by graphics3d.cpp.
bool gfx_has_fill();
Color gfx_fill_color();
bool gfx_has_stroke();
Color gfx_stroke_color();
float gfx_stroke_size();
int gfx_segments();

// Invalidation of the 3D mesh cache, defined in graphics3d.cpp.
void reset3d_shape_cache();

// Bridges from 2D to 3D, defined in graphics3d.cpp.
void end3d_internal();          // flush des buckets + EndMode3D (no-op hors bloc 3D)
void reset3d_lighting_state();   // resets the 3D lighting to its default state
void reset3d_graphics_state();   // frees the 3D GL resources, before the context is destroyed
void reset3d_frame_state();      // resets the current 3D texture; called every frame by reset_styles
void register3d_graphics(Value& m);   // enregistre les builtins 3D dans le module graphics

// Current 3D texture: a style state, saved and restored by push and pushStyle.
unsigned int gfx3d_get_texture();      // id GL de la texture 3D courante (0 = blanche)
void gfx3d_set_texture(unsigned int id);

// External models: the bytes are preloaded, the GPU load deferred.
#include <vector>
void model_preload_bytes(const std::string& name, std::vector<unsigned char> bytes, const std::string& ext);
