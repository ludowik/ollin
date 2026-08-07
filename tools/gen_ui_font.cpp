// Génère `src/modules/ui_font.h` : l'atlas de police embarqué du module `ui`.
//
// Outil de développement, exécuté À LA MAIN quand on change de police ou de jeu de
// caractères — il n'est PAS compilé par le build du moteur. Il s'appuie sur
// ExportFontAsCode (raylib), qui écrit l'atlas compressé et les métriques de chaque
// glyphe : le moteur n'a donc aucun fichier de police à trouver à l'exécution, et le
// même code fonctionne sur toutes les cibles, WASM compris.
//
//   c++ -std=c++17 tools/gen_ui_font.cpp -o /tmp/gen_ui_font \
//       -Ibuild-gfx/_deps/raylib-build/raylib/include \
//       build-gfx/_deps/raylib-build/raylib/libraylib.a -lm -lpthread -ldl -lGL -lX11
//   xvfb-run -a /tmp/gen_ui_font <police.ttf> <taille>
//
// LoadFontEx crée une texture, donc un contexte graphique est nécessaire : d'où la
// fenêtre minimale et l'affichage virtuel.
#include <raylib.h>
#include <cstdio>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
    const char* path = (argc > 1) ? argv[1] : "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
    int size = (argc > 2) ? atoi(argv[2]) : 32;

    // ASCII imprimable + les lettres accentuées du français (les libellés sont écrits
    // par l'utilisateur du langage, pas par le moteur).
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
        printf("échec du chargement : %s\n", path);
        CloseWindow();
        return 1;
    }
    ExportFontAsCode(font, "src/modules/ui_font.h");
    printf("police %s à %d px : %d glyphes, atlas %dx%d\n", path, size, font.glyphCount,
           font.texture.width, font.texture.height);
    UnloadFont(font);
    CloseWindow();
    return 0;
}
