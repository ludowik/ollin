#include "engine_font.h"
#include "font_mono.h"
#include "font_sans.h"
#include "graphics_internal.h"
#include "shader_sources.h"
#include <cstring>
#include <string>

namespace {

struct Entry {
    const char* name;
    Font (*load)();   // null means raylib's built-in font, already loaded and with no atlas
    Font font;
    bool ready;
    bool sdf;         // the atlas is a distance field, drawn through s_sdf
};

// The order fixes the indices; "sans" comes first and is the default.
Entry s_fonts[] = {
    {"sans", LoadFont_FontSans, {0}, false, true},
    {"mono", LoadFont_FontMono, {0}, false, true},
    {"pixel", nullptr, {0}, false, false},
};

// The margin, in atlas pixels, that raylib's SDF loader (FONT_SDF_CHAR_PADDING) leaves around every glyph
// so that the distance can fall off outside the outline.
const float SDF_MARGIN = 4.0f;

Shader s_sdf = {0};
bool s_sdf_ready = false;

void load_sdf_shader() {
    std::string fs = std::string(gfx_shader_header()) + k_sdf_fragment_src;
    s_sdf = LoadShaderFromMemory(nullptr, fs.c_str());   // nullptr = raylib's default 2D vertex shader
    s_sdf_ready = true;
}

const int FONT_COUNT = (int)(sizeof(s_fonts) / sizeof(s_fonts[0]));

} // namespace

int engine_font_count() {
    return FONT_COUNT;
}

const char* engine_font_name(int idx) {
    if (idx < 0 || idx >= FONT_COUNT)
        return "";
    return s_fonts[idx].name;
}

int engine_font_index(const char* name) {
    for (int i = 0; i < FONT_COUNT; ++i) {
        if (strcmp(s_fonts[i].name, name) == 0)
            return i;
    }
    return -1;
}

int engine_font_default() {
    return 0;
}

Font engine_font(int idx) {
    if (idx < 0 || idx >= FONT_COUNT)
        idx = engine_font_default();
    Entry& e = s_fonts[idx];
    if (e.load == nullptr)
        return GetFontDefault();
    if (!e.ready && IsWindowReady()) {
        e.font = e.load();
        if (e.font.texture.id != 0) {
            // Bilinear: a distance field is only a distance once it is interpolated, and a bitmap atlas
            // is usually scaled down, so it smooths the outlines where nearest would leave them jagged.
            SetTextureFilter(e.font.texture, TEXTURE_FILTER_BILINEAR);
            if (e.sdf && !s_sdf_ready)
                load_sdf_shader();
            e.ready = true;
        }
    }
    return e.ready ? e.font : GetFontDefault();
}

void engine_draw_text(int idx, const char* text, Vector2 pos, float size, float spacing, Color color) {
    if (idx < 0 || idx >= FONT_COUNT)
        idx = engine_font_default();
    Font font = engine_font(idx);
    bool sdf = s_fonts[idx].sdf && s_fonts[idx].ready && s_sdf_ready;
    if (sdf)
        BeginShaderMode(s_sdf);
    DrawTextEx(font, text, pos, size, spacing, color);
    if (sdf)
        EndShaderMode();
}

void engine_font_reset() {
    for (int i = 0; i < FONT_COUNT; ++i)
        s_fonts[i].ready = false;
    s_sdf_ready = false;   // the shader belongs to the previous program's context, like the textures
}

// Read off a capital: 'H' has neither descender nor overshoot, so the bottom of its box IS the
// baseline, and offsetY + height is the ascent at the atlas's own size. The fraction is the
// fallback for a font whose 'H' cannot be found — the registry decides its fallback metric as it
// decides its fallback font.
float engine_font_ascent(const Font& font, float size) {
    int i = GetGlyphIndex(font, 'H');
    if (i < 0 || i >= font.glyphCount)
        return size * 0.8f;
    float ascent = (float)font.glyphs[i].offsetY + font.recs[i].height;
    for (const Entry& e : s_fonts) {
        if (e.sdf && e.ready && e.font.texture.id == font.texture.id)
            ascent -= SDF_MARGIN;   // the rectangle of an SDF glyph reaches one margin below the baseline
    }
    return ascent * size / (float)font.baseSize;
}
