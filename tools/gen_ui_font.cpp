// Generates an embedded font atlas: `src/modules/font_<name>.h`.
//
// A development tool, run BY HAND when the font or the character set changes — it is NOT
// compiled by the engine's build. It relies on ExportFontAsCode (raylib), which writes the
// compressed atlas and every glyph's metrics: the engine therefore has no font file to find
// at runtime, and the same code works on every target, WASM included.
//
//   c++ -std=c++17 tools/gen_ui_font.cpp -o /tmp/gen_ui_font \
//       -Ibuild-gfx/_deps/raylib-build/raylib/include \
//       build-gfx/_deps/raylib-build/raylib/libraylib.a -lm -lpthread -ldl -lGL -lX11
//   xvfb-run -a /tmp/gen_ui_font <font.ttf> <size> <name>
//
// LoadFontEx creates a texture, so a graphics context is needed: hence the minimal window
// and the virtual display.
#include <raylib.h>
#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
    const char* path = (argc > 1) ? argv[1] : "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
    int size = (argc > 2) ? atoi(argv[2]) : 32;
    const char* name = (argc > 3) ? argv[3] : "sans";

    // Printable ASCII plus the accented letters of French (the labels are written by the
    // language's user, not by the engine).
    std::vector<int> points;
    for (int c = 32; c <= 126; ++c)
        points.push_back(c);
    const char* extra = "°àâäçéèêëîïôöùûüÿÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸœŒ«»…–—";
    int count = 0;
    int* decoded = LoadCodepoints(extra, &count);
    for (int i = 0; i < count; ++i)
        points.push_back(decoded[i]);
    UnloadCodepoints(decoded);

    SetTraceLogLevel(LOG_WARNING);
    InitWindow(64, 64, "gen_ui_font");
    Font font = LoadFontEx(path, size, points.data(), (int)points.size());
    if (font.texture.id == 0) {
        printf("failed to load: %s\n", path);
        CloseWindow();
        return 1;
    }
    ExportFontAsCode(font, TextFormat("src/modules/font_%s.h", name));
    printf("font %s at %d px: %d glyphs, atlas %dx%d\n", path, size, font.glyphCount,
           font.texture.width, font.texture.height);
    UnloadFont(font);
    CloseWindow();
    return 0;
}
