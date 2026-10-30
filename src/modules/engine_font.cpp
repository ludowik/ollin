#include "engine_font.h"
#include "font_mono.h"
#include "font_sans.h"
#include "shader_sources.h"
#include <cstring>
#include <string>

namespace {

struct Entry {
    const char* name;
    Font (*load)();   // null means raylib's built-in font, already loaded and with no atlas
    Font font;
    bool ready;
};

// The order fixes the indices; "sans" comes first and is the default.
Entry s_fonts[] = {
    {"sans", LoadFont_FontSans, {0}, false},
    {"mono", LoadFont_FontMono, {0}, false},
    {"pixel", nullptr, {0}, false},
};

const int FONT_COUNT = (int)(sizeof(s_fonts) / sizeof(s_fonts[0]));

// An unknown index falls back to the default font.
Entry& entry_for(int idx) {
    if (idx < 0 || idx >= FONT_COUNT)
        idx = engine_font_default();
    return s_fonts[idx];
}

// The embedded atlases are signed distance fields (tools/gen_ui_font.cpp); the built-in font, which has no
// loader, is a plain bitmap.
bool is_sdf(const Entry& e) {
    return e.load != nullptr;
}

// The margin, in atlas pixels, that raylib's SDF loader (FONT_SDF_CHAR_PADDING) leaves around every glyph
// so that the distance can fall off outside the outline.
const float SDF_MARGIN = 4.0f;

Shader s_sdf = {0};
bool s_sdf_ready = false;
bool s_text_run_open = false;   // s_sdf is bound: see engine_text_run_end

void load_sdf_shader() {
    std::string fs = std::string(k_shader_header) + k_sdf_fragment_src;
    s_sdf = LoadShaderFromMemory(nullptr, fs.c_str());   // nullptr = raylib's default 2D vertex shader
    s_sdf_ready = true;
}

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
    Entry& e = entry_for(idx);
    if (e.load == nullptr)
        return GetFontDefault();
    if (!e.ready && IsWindowReady()) {
        e.font = e.load();
        if (e.font.texture.id != 0) {
            // Bilinear: a distance field is only a distance once it is interpolated, and a bitmap atlas
            // is usually scaled down, so it smooths the outlines where nearest would leave them jagged.
            SetTextureFilter(e.font.texture, TEXTURE_FILTER_BILINEAR);
            if (!s_sdf_ready)
                load_sdf_shader();
            e.ready = true;
        }
    }
    return e.ready ? e.font : GetFontDefault();
}

bool engine_font_usable(int idx) {
    Font font = engine_font(idx);
    return font.texture.id != 0 && font.baseSize != 0;
}

Vector2 engine_text_size(int idx, const char* text, float size) {
    Font font = engine_font(idx);
    return MeasureTextEx(font, text, size, size / (float)font.baseSize);
}

void engine_text_run_end() {
    if (s_text_run_open) {
        s_text_run_open = false;
        EndShaderMode();   // draws what is pending through the distance-field shader, then restores the default
    }
}

void engine_draw_text(int idx, const char* text, Vector2 pos, float size, Color color) {
    Entry& e = entry_for(idx);
    Font font = engine_font(idx);
    if (is_sdf(e) && e.ready) {
        if (!s_text_run_open) {
            BeginShaderMode(s_sdf);
            s_text_run_open = true;
        }
    } else {
        engine_text_run_end();   // a bitmap font is read as it is: its soft edge would be cut by the shader
    }
    DrawTextEx(font, text, pos, size, size / (float)font.baseSize, color);
}

void engine_font_reset() {
    // A frame that failed halfway (a throw the frame's own handler does not see) leaves the shader bound, and
    // in the browser the context outlives the program; a second canvas() reaches here too.
    if (IsWindowReady())
        engine_text_run_end();
    s_text_run_open = false;
    for (int i = 0; i < FONT_COUNT; ++i)
        s_fonts[i].ready = false;
    s_sdf_ready = false;   // the shader belongs to the previous program's context, like the textures
}

// Read off a capital: 'H' has neither descender nor overshoot, so the bottom of its box IS the
// baseline, and offsetY + height is the ascent at the atlas's own size. The fraction is the
// fallback for a font whose 'H' cannot be found — the registry decides its fallback metric as it
// decides its fallback font.
float engine_font_ascent(int idx, float size) {
    Entry& e = entry_for(idx);
    Font font = engine_font(idx);
    int i = GetGlyphIndex(font, 'H');
    if (i < 0 || i >= font.glyphCount)
        return size * 0.8f;
    float ascent = (float)font.glyphs[i].offsetY + font.recs[i].height;
    if (is_sdf(e) && e.ready)
        ascent -= SDF_MARGIN;   // the rectangle of an SDF glyph reaches one margin below the baseline
    return ascent * size / (float)font.baseSize;
}
