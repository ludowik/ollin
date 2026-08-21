#include "engine_font.h"
#include "font_mono.h"
#include "font_sans.h"
#include <cstring>

namespace {

struct Entry {
    const char* name;
    Font (*load)();   // nul = police intégrée de raylib (déjà chargée, sans atlas)
    Font font;
    bool ready;
};

// The order fixes the indices; "sans" comes first and is the default font.
Entry s_fonts[] = {
    {"sans", LoadFont_FontSans, {0}, false},
    {"mono", LoadFont_FontMono, {0}, false},
    {"pixel", nullptr, {0}, false},
};

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
            // The atlas is rendered at 32 px and usually scaled down, so bilinear filtering
            // smooths the outlines where a nearest filter would leave them jagged.
            SetTextureFilter(e.font.texture, TEXTURE_FILTER_BILINEAR);
            e.ready = true;
        }
    }
    return e.ready ? e.font : GetFontDefault();
}

void engine_font_reset() {
    for (int i = 0; i < FONT_COUNT; ++i)
        s_fonts[i].ready = false;
}
