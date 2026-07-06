#include "image_module.h"
#include "value.h"
#include "vm.h"
#include "image_module.h"
#include "keyboard_module.h"
#include "mouse_module.h"
#include <raylib.h>
#include <rlgl.h>
#include <stdexcept>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

static int toInt(const Value& v) {
    if (v.isInteger())
        return (int)v.asInt();
    if (v.isFloat())
        return (int)v.asFloat();
    return 0;
}

static Color toColor(const Value& v) {
    if (!v.isMap() && !v.isClass())
        throw std::runtime_error("expected a Color object");
    auto getComp = [&](const char* k, double def) -> uint8_t {
        Value f = v.mapGet(Value(std::string(k)));
        return f.isNumber() ? (uint8_t)(f.asNum() * 255.0 + 0.5) : (uint8_t)(def * 255.0 + 0.5);
    };
    return {getComp("r", 0), getComp("g", 0), getComp("b", 0), getComp("a", 1)};
}

// Composante [0,1] → octet [0,255] (bornée).
static uint8_t comp01(double v) {
    if (v < 0.0)
        v = 0.0;
    if (v > 1.0)
        v = 1.0;
    return (uint8_t)(v * 255.0 + 0.5);
}

static Color rgbaColor(double r, double g, double b, double a) {
    return {comp01(r), comp01(g), comp01(b), comp01(a)};
}

static int s_physW = 0, s_physH = 0;
static int s_logicalW = 0; // largeur logique de la zone (pour l'overlay FPS en haut à droite)
static int s_logicalH = 0; // hauteur logique de la zone
// Contexte de dessin PERSISTANT : draw() rend dans cette RenderTexture, qui n'est
// PAS effacée entre les frames (c'est à draw() d'appeler graphics.clear() s'il
// veut repartir d'un fond net). Elle est re-affichée à l'écran chaque frame, avec
// l'overlay FPS PAR-DESSUS (donc l'overlay reste net, il ne bave pas).
static RenderTexture2D s_target{};
static bool s_target_ready = false;
static int s_targetW = 0, s_targetH = 0;   // taille réelle de la RT (sur-échantillonnée)
// Sur-échantillonnage visé RELATIF au logique (anti-aliasing), borné par la
// résolution physique et un plafond (cf. gfx_canvas) — PAS multiplié par le DPR.
static const int SSAA = 2;
// Mode de fusion courant (choisi par graphics.blendMode), suivi pour pouvoir le
// restaurer après un fondu (clear avec alpha) et le remettre à ALPHA chaque frame.
static int s_blend_mode = BLEND_ALPHA;
// Capture d'écran DIFFÉRÉE en fin de frame (draw() rend dans la RT ; la capture
// doit lire l'écran composé). Remis à zéro à chaque gfx_canvas (pas de fuite
// d'une requête d'un programme précédent dans l'instance WASM partagée).
static std::string s_shot_path;
static bool s_shot_pending = false;
static void flushPendingScreenshot();   // défini plus bas (utilisé par gfx_end_draw)

static Value gfx_canvas(Value* args, int argc) {
    int w = argc > 0 ? toInt(args[0]) : 800;
    int h = argc > 1 ? toInt(args[1]) : 600;
    const char* title = (argc > 2 && args[2].isString()) ? args[2].asString().c_str() : "Ollin";
    s_shot_pending = false;   // nouveau programme → oublier une capture en attente
    s_blend_mode = BLEND_ALPHA;
#ifdef __EMSCRIPTEN__
    if (IsWindowReady()) {
        if (s_target_ready) {                 // libérer l'ancienne cible AVANT de perdre le contexte GL
            UnloadRenderTexture(s_target);
            s_target_ready = false;
        }
        CloseWindow();
    }
    double dpr = EM_ASM_DOUBLE({ return window.devicePixelRatio || 1.0; });
    s_physW = (int)(w * dpr + 0.5);
    s_physH = (int)(h * dpr + 0.5);
    // InitWindow with logical dimensions — sets projection [0,w]×[0,h]
    EM_ASM({
        var o = document.getElementById('output');
        if (o)
            o.style.display = 'none';
    });
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    InitWindow(w, h, title);
    SetTargetFPS(0);
    // Override canvas bitmap to physical resolution, CSS display to logical size
    // rlViewport in emscripten_frame will render to the full physical bitmap
    EM_ASM(
        {
            var c = document.getElementById('canvas');
            if (c) {
                c.width = $0;
                c.height = $1;
                c.style.width = $2 + 'px';
                c.style.height = $3 + 'px';
                c.style.display = 'block';
            }
        },
        s_physW, s_physH, w, h);
#else
    if (IsWindowReady() && s_target_ready) {
        UnloadRenderTexture(s_target);
        s_target_ready = false;
    }
    s_physW = w;
    s_physH = h;
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    InitWindow(w, h, title);
    SetTargetFPS(60);
#endif
    s_logicalW = w;
    s_logicalH = h;
    // Cible de rendu persistante. On vise un sur-échantillonnage RELATIF au
    // logique (~SSAA×) pour l'anti-aliasing, MAIS sans jamais descendre sous la
    // résolution physique (netteté HiDPI). On NE multiplie donc PAS SSAA par le
    // DPR (sinon sur mobile dpr≥2 la texture explosait : mémoire + dépassement de
    // GL_MAX_TEXTURE_SIZE → écran noir). La taille est en plus plafonnée.
    const int MAX_RT = 4096;   // borne sûre (≤ GL_MAX_TEXTURE_SIZE sur la plupart des GPU)
    s_targetW = s_physW > s_logicalW * SSAA ? s_physW : s_logicalW * SSAA;
    s_targetH = s_physH > s_logicalH * SSAA ? s_physH : s_logicalH * SSAA;
    if (s_targetW > MAX_RT) {
        s_targetW = MAX_RT;
    }
    if (s_targetH > MAX_RT) {
        s_targetH = MAX_RT;
    }
    s_target = LoadRenderTexture(s_targetW, s_targetH);
    // Vérifie l'allocation : si le FBO/la texture n'a pas été créé (taille trop
    // grande, VRAM insuffisante…), on reste en rendu DIRECT (renderFrame bascule
    // sur le repli) au lieu d'échantillonner une texture invalide (écran noir).
    s_target_ready = (s_target.id != 0 && s_target.texture.id != 0);
    if (s_target_ready) {
        SetTextureFilter(s_target.texture, TEXTURE_FILTER_BILINEAR);   // lissage à la réduction
        BeginTextureMode(s_target);
        ClearBackground(BLACK);
        EndTextureMode();
    }
    Value win = VM::current()->getGlobal("window");
    if (win.isMap()) {
        win.mapSet(Value(std::string("width")), Value((int64_t)w));
        win.mapSet(Value(std::string("height")), Value((int64_t)h));
    }
    return Value{};
}

static Value gfx_is_open(Value* args, int argc) {
    (void)args;
    (void)argc;
    return Value(WindowShouldClose() ? int64_t(0) : int64_t(1));
}

static Value gfx_begin_draw(Value* args, int argc) {
    (void)args;
    (void)argc;
    BeginDrawing();
    return Value{};
}

static Value gfx_end_draw(Value* args, int argc) {
    (void)args;
    (void)argc;
    flushPendingScreenshot();   // chemin manuel begin_draw/end_draw : capture ici
    EndDrawing();
    return Value{};
}

static Value gfx_clear(Value* args, int argc) {
    Color c = argc > 0 ? toColor(args[0]) : BLACK;
    if (c.a < 255) {
        // Couleur semi-transparente → FONDU (comme p5.js background(r,g,b,a<255))
        // et NON un effacement net : on peint un rectangle plein écran translucide
        // en fusion ALPHA, qui estompe le contenu persistant vers `c`. Idéal pour
        // des traînées. On force ALPHA le temps du rectangle puis on restaure le
        // mode de fusion courant (celui posé par graphics.blendMode dans draw()).
        BeginBlendMode(BLEND_ALPHA);
        rlPushMatrix();                 // fondu indépendant de la transfo courante
        rlLoadIdentity();               // (comme ClearBackground) → couvre tout le canvas
        DrawRectangle(0, 0, s_logicalW, s_logicalH, c);
        rlPopMatrix();
        BeginBlendMode(s_blend_mode);
    } else {
        ClearBackground(c);   // opaque → effacement net (glClear)
    }
    return Value{};
}

// Mode de fusion des dessins suivants. Accepte une chaîne ("alpha", "add",
// "multiply", "subtract", "add_colors", "premultiply") ou une constante du
// module `blend`. Remis à "alpha" au début de chaque frame (resetStyles).
static Value gfx_blend_mode(Value* args, int argc) {
    int mode = BLEND_ALPHA;
    if (argc > 0 && args[0].isString()) {
        const std::string& s = args[0].asString();
        if (s == "alpha") {
            mode = BLEND_ALPHA;
        } else if (s == "add" || s == "additive") {
            mode = BLEND_ADDITIVE;
        } else if (s == "multiply" || s == "multiplied") {
            mode = BLEND_MULTIPLIED;
        } else if (s == "add_colors") {
            mode = BLEND_ADD_COLORS;
        } else if (s == "subtract") {
            mode = BLEND_SUBTRACT_COLORS;
        } else if (s == "premultiply") {
            mode = BLEND_ALPHA_PREMULTIPLY;
        } else {
            throw std::runtime_error("graphics.blendMode: mode inconnu '" + s + "'");
        }
    } else if (argc > 0 && args[0].isNumber()) {
        mode = (int)args[0].asNum();   // constante du module `blend`
    }
    s_blend_mode = mode;
    BeginBlendMode(mode);
    return Value{};
}

// ── Style state ───────────────────────────────────────────────────────────────
static float s_stroke_size = 2.0f;
static bool s_has_stroke = true;
static Color s_stroke_color = WHITE;
static bool s_has_fill = false;
static Color s_fill_color = WHITE;

static void applyStrokeSize(float sz) {
    s_stroke_size = sz;
}
static void applyStroke(bool en, Color c = WHITE) {
    s_has_stroke = en;
    s_stroke_color = c;
}
static void applyFill(bool en, Color c = WHITE) {
    s_has_fill = en;
    s_fill_color = c;
}

static void resetStyles() {
    applyStrokeSize(2.0f);
    applyStroke(true, WHITE);
    applyFill(false);
    image_set_tint(false, 255, 255, 255, 255);   // pas de teinte par défaut (comme fill/stroke, remis chaque frame)
    s_blend_mode = BLEND_ALPHA;                   // mode de fusion remis par défaut chaque frame
    BeginBlendMode(BLEND_ALPHA);
    rlLoadIdentity();
}

static Value gfx_stroke_size(Value* args, int argc) {
    if (argc > 0 && args[0].isNumber())
        applyStrokeSize((float)args[0].asNum());
    return Value{};
}

static Value gfx_stroke(Value* args, int argc) {
    if (argc >= 3 && args[0].isNumber() && args[1].isNumber() && args[2].isNumber()) {
        double a = (argc > 3 && args[3].isNumber()) ? args[3].asNum() : 1.0;   // r, g, b [, a] directs
        applyStroke(true, rgbaColor(args[0].asNum(), args[1].asNum(), args[2].asNum(), a));
    } else if (argc > 0 && (args[0].isMap() || args[0].isClass())) {
        applyStroke(true, toColor(args[0]));   // objet Color (+ taille optionnelle en 2e arg)
        if (argc > 1 && args[1].isNumber())
            applyStrokeSize((float)args[1].asNum());
    } else {
        s_has_stroke = true;                   // sans argument → (ré)active avec la couleur courante
    }
    return Value{};
}

static Value gfx_no_stroke(Value* args, int argc) {
    (void)args;
    (void)argc;
    s_has_stroke = false;                       // ne plus dessiner de contour (couleur conservée)
    return Value{};
}

static Value gfx_fill(Value* args, int argc) {
    if (argc >= 3 && args[0].isNumber() && args[1].isNumber() && args[2].isNumber()) {
        double a = (argc > 3 && args[3].isNumber()) ? args[3].asNum() : 1.0;   // r, g, b [, a] directs
        applyFill(true, rgbaColor(args[0].asNum(), args[1].asNum(), args[2].asNum(), a));
    } else if (argc > 0 && (args[0].isMap() || args[0].isClass())) {
        applyFill(true, toColor(args[0]));   // objet Color
    } else {
        s_has_fill = true;                   // sans argument → (ré)active avec la couleur courante
    }
    return Value{};
}

static Value gfx_no_fill(Value* args, int argc) {
    (void)args;
    (void)argc;
    s_has_fill = false;                       // ne plus remplir (couleur conservée)
    return Value{};
}

// Teinte globale des images (graphics.sprite / image.draw) : objet Color ou r,g,b[,a].
static Value gfx_tint(Value* args, int argc) {
    Color c;
    if (argc >= 3 && args[0].isNumber() && args[1].isNumber() && args[2].isNumber()) {
        double a = (argc > 3 && args[3].isNumber()) ? args[3].asNum() : 1.0;
        c = rgbaColor(args[0].asNum(), args[1].asNum(), args[2].asNum(), a);
    } else if (argc > 0 && (args[0].isMap() || args[0].isClass())) {
        c = toColor(args[0]);
    } else {
        return Value{};   // sans argument valide : ne change rien
    }
    image_set_tint(true, c.r, c.g, c.b, c.a);
    return Value{};
}

static Value gfx_no_tint(Value* args, int argc) {
    (void)args;
    (void)argc;
    image_set_tint(false, 255, 255, 255, 255);
    return Value{};
}

static Value gfx_line(Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("graphics.line: expected x1, y1, x2, y2");
    if (!s_has_stroke)
        return Value{};
    float x1 = (float)args[0].asNum();
    float y1 = (float)args[1].asNum();
    float x2 = (float)args[2].asNum();
    float y2 = (float)args[3].asNum();
    if (s_stroke_size <= 1.0f)
        DrawLine((int)x1, (int)y1, (int)x2, (int)y2, s_stroke_color);
    else
        DrawLineEx({x1, y1}, {x2, y2}, s_stroke_size, s_stroke_color);
    return Value{};
}

static Value gfx_rect(Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("graphics.rect: expected x, y, w, h");
    int x = toInt(args[0]);
    int y = toInt(args[1]);
    int w = toInt(args[2]);
    int h = toInt(args[3]);
    if (s_has_fill)
        DrawRectangle(x, y, w, h, s_fill_color);
    if (s_has_stroke)
        DrawRectangleLinesEx({(float)x, (float)y, (float)w, (float)h}, s_stroke_size, s_stroke_color);
    return Value{};
}

static Value gfx_fps(Value* args, int argc) {
    (void)args;
    (void)argc;
    return Value((int64_t)GetFPS());
}

// Capture le framebuffer AFFICHÉ dans un PNG. Comme draw() rend dans la
// RenderTexture persistante (liée pendant draw), on ne peut pas capturer l'écran
// composité ici : on DIFFÈRE la capture à la fin de la frame (après composition),
// dans renderFrame (ou dans gfx_end_draw pour le chemin manuel). Sur WASM,
// TakeScreenshot déclenche un téléchargement. (s_shot_path/s_shot_pending : voir haut.)
static Value gfx_screenshot(Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("graphics.screenshot: expected a file path");
    s_shot_path = args[0].asString();
    s_shot_pending = true;
    return Value{};
}

// Exécute une capture en attente : appelé en fin de frame par renderFrame, quand
// le framebuffer par défaut contient l'image composée (écran réellement affiché).
static void flushPendingScreenshot() {
    if (!s_shot_pending)
        return;
    s_shot_pending = false;
    rlDrawRenderBatchActive();
    TakeScreenshot(s_shot_path.c_str());
}

static Value gfx_draw_text(Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("graphics.draw_text: expected text, x, y, size [, color]");
    const char* text = args[0].isString() ? args[0].asString().c_str() : "";
    DrawText(text, toInt(args[1]), toInt(args[2]), toInt(args[3]), argc > 4 ? toColor(args[4]) : s_stroke_color);
    return Value{};
}

static Value gfx_close(Value* args, int argc) {
    (void)args;
    (void)argc;
    CloseWindow();
    return Value{};
}

// ── Polygon ───────────────────────────────────────────────────────────────────
static void polyFill(std::vector<Vector2> pts, Color color) {
    int n = (int)pts.size();
    if (n < 3)
        return;
    // Normalise vers CCW (coordonnées écran Y↓ : shoelace > 0 = CW → inverser)
    float area = 0;
    for (int i = 0; i < n; i++) {
        const auto& a = pts[i];
        const auto& b = pts[(i + 1) % n];
        area += (b.x - a.x) * (b.y + a.y);
    }
    if (area > 0)
        std::reverse(pts.begin(), pts.end());
    // Fan depuis le centroïde
    float cx = 0, cy = 0;
    for (const auto& p : pts) {
        cx += p.x;
        cy += p.y;
    }
    cx /= n;
    cy /= n;
    Vector2 hub = {cx, cy};
    for (int i = 0; i < n; i++)
        DrawTriangle(hub, pts[(i + 1) % n], pts[i], color);
}

static std::vector<Vector2> parsePoints(const Value& v) {
    std::vector<Vector2> pts;
    if (!v.isArray())
        return pts;
    const auto& items = v.aptr->items;
    if (items.empty())
        return pts;
    if (items[0].isArray()) {
        for (const auto& p : items) {
            if (!p.isArray() || p.aptr->items.size() < 2)
                continue;
            pts.push_back({(float)p.aptr->items[0].asNum(), (float)p.aptr->items[1].asNum()});
        }
    } else {
        for (size_t i = 0; i + 1 < items.size(); i += 2)
            pts.push_back({(float)items[i].asNum(), (float)items[i + 1].asNum()});
    }
    return pts;
}

static Value gfx_polygon(Value* args, int argc) {
    if (argc < 1 || !args[0].isArray())
        throw std::runtime_error("graphics.polygon: expected array of points");
    auto pts = parsePoints(args[0]);
    if ((int)pts.size() < 3)
        return Value{};
    if (s_has_fill)
        polyFill(pts, s_fill_color);
    if (s_has_stroke) {
        int n = (int)pts.size();
        for (int i = 0; i < n; i++)
            DrawLineEx(pts[i], pts[(i + 1) % n], s_stroke_size, s_stroke_color);
    }
    return Value{};
}

static Value gfx_polyline(Value* args, int argc) {
    if (argc < 1 || !args[0].isArray())
        throw std::runtime_error("graphics.polyline: expected array of points");
    if (!s_has_stroke)
        return Value{};
    auto pts = parsePoints(args[0]);
    int n = (int)pts.size();
    for (int i = 0; i < n - 1; i++)
        DrawLineEx(pts[i], pts[i + 1], s_stroke_size, s_stroke_color);
    return Value{};
}

static void drawEllipseStroke(float cx, float cy, float rx, float ry, float thick, Color color, int segs) {
    float prev_x = cx + rx, prev_y = cy;
    for (int i = 1; i <= segs; i++) {
        float a = (float)i / segs * 2.0f * PI;
        float nx = cx + rx * cosf(a);
        float ny = cy + ry * sinf(a);
        DrawLineEx({prev_x, prev_y}, {nx, ny}, thick, color);
        prev_x = nx;
        prev_y = ny;
    }
}

static void drawEllipseFill(float cx, float cy, float rx, float ry, Color color, int segs) {
    for (int i = 0; i < segs; i++) {
        float a0 = (float)i / segs * 2.0f * PI;
        float a1 = (float)(i + 1) / segs * 2.0f * PI;
        DrawTriangle({cx, cy}, {cx + rx * cosf(a1), cy + ry * sinf(a1)}, {cx + rx * cosf(a0), cy + ry * sinf(a0)},
                     color);
    }
}

static void drawOval(float cx, float cy, float rx, float ry, int segs) {
    if (s_has_fill)
        drawEllipseFill(cx, cy, rx, ry, s_fill_color, segs);
    if (s_has_stroke)
        drawEllipseStroke(cx, cy, rx, ry, s_stroke_size, s_stroke_color, segs);
}

static Value gfx_ellipse(Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("graphics.ellipse: expected x, y, width, height");
    int segs = (argc > 4 && args[4].isNumber()) ? std::max(3, (int)args[4].asNum()) : 32;
    drawOval((float)args[0].asNum(), (float)args[1].asNum(), (float)args[2].asNum() * 0.5f,
             (float)args[3].asNum() * 0.5f, segs);
    return Value{};
}

static Value gfx_circle(Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("graphics.circle: expected x, y, radius");
    int segs = (argc > 3 && args[3].isNumber()) ? std::max(3, (int)args[3].asNum()) : 32;
    float r = (float)args[2].asNum();
    drawOval((float)args[0].asNum(), (float)args[1].asNum(), r, r, segs);
    return Value{};
}

static Value gfx_point(Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("graphics.point: expected x, y");
    if (!s_has_stroke)
        return Value{};
    float x = (float)args[0].asNum();
    float y = (float)args[1].asNum();
    DrawCircleV({x, y}, s_stroke_size, s_stroke_color);
    return Value{};
}

static bool s_quit = false;

// Overlay FPS dessiné par le moteur après chaque frame (toujours en haut à
// droite de la zone graphique). Couleur vive + ombre → lisible sur tout fond.
static void drawFpsOverlay() {
    const char* buf = TextFormat("FPS: %d", GetFPS());
    const int size = 16, margin = 8;
    int tw = MeasureText(buf, size);
    int x = s_logicalW - tw - margin;
    int y = margin;
    DrawText(buf, x + 1, y + 1, size, BLACK);     // ombre (contraste)
    DrawText(buf, x, y, size, {0, 228, 48, 255}); // vert vif (lime)
}

static Value gfx_quit(Value* args, int argc) {
    (void)args;
    (void)argc;
#ifdef __EMSCRIPTEN__
    emscripten_cancel_main_loop();
#else
    s_quit = true;
#endif
    return Value{};
}

// Temps accumulé depuis le démarrage du programme (remis à 0 à chaque gfx_run).
static double s_elapsed_time = 0.0;

// Met à jour deltaTime/elapsedTime dans la VM et appelle update(dt) si définie.
static Value s_update_callback;
static void callUpdateIfAny() {
    double dt = (double)GetFrameTime();
    s_elapsed_time += dt;
    VM* vm = VM::current();
    vm->setGlobal("deltaTime", Value(dt));
    vm->setGlobal("elapsedTime", Value(s_elapsed_time));
    if (s_update_callback.isCallable())
        vm->callValue(s_update_callback, Value(dt));
}

// Rend UNE frame. Le contexte n'est PAS effacé d'office : draw() dessine dans la
// cible persistante s_target (c'est à draw() d'appeler graphics.clear() s'il veut
// repartir d'un fond net), puis on ré-affiche s_target à l'écran et on pose
// l'overlay FPS PAR-DESSUS (donc net, jamais accumulé). `tex`/`drawing` renvoient
// l'état des blocs ouverts pour un nettoyage sûr si draw() lève (boucle web).
// Prélude commun d'une frame : styles par défaut, entrées, logique (update),
// puis rendu utilisateur (draw). Partagé par les deux chemins de renderFrame.
static void runUserCallbacks(const Value& drawFn) {
    resetStyles();
    keyboardPoll();
    mousePoll();
    callUpdateIfAny();
    VM::current()->callValue(const_cast<Value&>(drawFn));
}

static void renderFrame(const Value& drawFn, bool* tex, bool* drawing) {
    *tex = false;
    *drawing = false;
    if (s_target_ready) {
        BeginTextureMode(s_target);   // lie le FBO ; N'EFFACE PAS
        *tex = true;
        // La RT est en résolution physique, mais BeginTextureMode a posé une
        // projection en pixels physiques. On la remplace par les extents LOGIQUES
        // (origine haut-gauche, comme raylib) → draw() garde les coordonnées
        // logiques [0,w]×[0,h] tout en rendant à pleine résolution physique.
        // (Sur la PROJECTION, pas la modelview → survit à graphics.resetTransform.)
        rlMatrixMode(RL_PROJECTION);
        rlLoadIdentity();
        rlOrtho(0, s_logicalW, s_logicalH, 0, 0.0, 1.0);
        rlMatrixMode(RL_MODELVIEW);
        rlLoadIdentity();
        runUserCallbacks(drawFn);
        *tex = false;
        EndTextureMode();

        BeginDrawing();
        *drawing = true;
        if (s_physW != GetScreenWidth() || s_physH != GetScreenHeight())
            rlViewport(0, 0, s_physW, s_physH);
        // Composition OPAQUE (src=ONE, dst=ZERO) : on recopie le RGB du RT tel
        // quel, en ignorant SON canal alpha — sinon un RT à alpha faible (après un
        // fondu clear(...,a) ou des dessins translucides) apparaîtrait fantomatique.
        // Indispensable aussi pour ne PAS hériter du blend mode laissé par draw()
        // (ex. ADD), qui fausserait la composition et l'overlay.
        rlSetBlendFactors(RL_ONE, RL_ZERO, RL_FUNC_ADD);
        BeginBlendMode(BLEND_CUSTOM);
        // s_target est en pixels SSAA×physiques et stockée bottom-up → source =
        // taille réelle de la RT, hauteur négative pour l'afficher à l'endroit ;
        // destination en coordonnées logiques (remplit l'écran via le viewport
        // physique). La réduction SSAA→physique par le filtre bilinéaire lisse.
        DrawTexturePro(s_target.texture,
                       Rectangle{0.0f, 0.0f, (float)s_targetW, -(float)s_targetH},
                       Rectangle{0.0f, 0.0f, (float)s_logicalW, (float)s_logicalH},
                       Vector2{0.0f, 0.0f}, 0.0f, WHITE);
        flushPendingScreenshot();      // capture l'écran composé (avant l'overlay FPS)
        BeginBlendMode(BLEND_ALPHA);   // overlay FPS en fusion normale
        drawFpsOverlay();
        *drawing = false;
        EndDrawing();
    } else {
        // Repli : aucun canvas persistant configuré → rendu direct (ancien comportement).
        BeginDrawing();
        *drawing = true;
        if (s_physW != GetScreenWidth() || s_physH != GetScreenHeight())
            rlViewport(0, 0, s_physW, s_physH);
        runUserCallbacks(drawFn);
        flushPendingScreenshot();      // capture l'écran (avant l'overlay FPS)
        drawFpsOverlay();
        *drawing = false;
        EndDrawing();
    }
}

#ifdef __EMSCRIPTEN__
static Value s_run_callback;
static void emscripten_frame() {
    // Une erreur d'exécution dans update()/draw() survient ici, hors du try/catch
    // de ollin_run (la boucle est asynchrone). Sans capture, l'exception ferait
    // planter le WASM en silence (écran figé). On l'attrape, on stoppe la boucle
    // et on remonte le message au playground pour l'afficher à la place du canvas.
    bool tex = false, drawing = false;
    try {
        renderFrame(s_run_callback, &tex, &drawing);
    } catch (const std::exception& e) {
        if (tex)                   // refermer les blocs restés ouverts (pas de 2× End…)
            EndTextureMode();
        if (drawing)
            EndDrawing();
        emscripten_cancel_main_loop();
        EM_ASM({
            if (typeof window !== 'undefined' && window.__ollinFrameError)
                window.__ollinFrameError(UTF8ToString($0));
        }, e.what());
    }
}
#endif

static Value gfx_run(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("graphics.run: expected callback function");
    Value fn = args[0];
    s_elapsed_time = 0.0;
    s_update_callback = VM::current()->getGlobal("update");
#ifdef __EMSCRIPTEN__
    s_run_callback = fn;
    emscripten_set_main_loop(emscripten_frame, 0, 0);
#else
    s_quit = false;
    while (!WindowShouldClose() && !s_quit) {
        bool tex = false, drawing = false;
        renderFrame(fn, &tex, &drawing);
    }
    if (s_target_ready) {
        UnloadRenderTexture(s_target);
        s_target_ready = false;
    }
    CloseWindow();
#endif
    return Value{};
}

// ── Transformations matricielles ──────────────────────────────────────────────
static Value gfx_push(Value* args, int argc) {
    (void)args;
    (void)argc;
    rlPushMatrix();
    return Value{};
}

static Value gfx_pop(Value* args, int argc) {
    (void)args;
    (void)argc;
    rlPopMatrix();
    return Value{};
}

static Value gfx_translate(Value* args, int argc) {
    if (argc < 2)
        throw std::runtime_error("graphics.translate: expected x, y");
    rlTranslatef((float)args[0].asNum(), (float)args[1].asNum(), 0.0f);
    return Value{};
}

static Value gfx_rotate(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("graphics.rotate: expected angle (degrees)");
    rlRotatef((float)args[0].asNum(), 0.0f, 0.0f, 1.0f);
    return Value{};
}

static Value gfx_scale(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("graphics.scale: expected sx [, sy]");
    float sx = (float)args[0].asNum();
    float sy = argc > 1 ? (float)args[1].asNum() : sx;
    rlScalef(sx, sy, 1.0f);
    return Value{};
}

static Value gfx_reset_transform(Value* args, int argc) {
    (void)args;
    (void)argc;
    rlLoadIdentity();
    return Value{};
}

// ── graphics.sprite(img, x, y [, w, h]) ──────────────────────────────────────

static Value gfx_sprite(Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("graphics.sprite: expected img, x, y");
    if (!args[0].isMap())
        throw std::runtime_error("graphics.sprite: expected image handle");
    Value idv = args[0].mapGet(Value(std::string("id")));
    if (!idv.isInteger())
        throw std::runtime_error("graphics.sprite: invalid image handle");
    int id = (int)idv.asInt();

    float x = (float)args[1].asNum();
    float y = (float)args[2].asNum();
    float dw = argc > 3 ? (float)args[3].asNum() : 0.0f;
    float dh = argc > 4 ? (float)args[4].asNum() : 0.0f;

    bool has = false;
    unsigned char r = 255, g = 255, b = 255, a = 255;
    image_get_tint(&has, &r, &g, &b, &a);
    image_draw_sprite(id, x, y, dw, dh, r, g, b, a);
    return Value{};
}

Value makeGraphicsModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("canvas")), Value::makeBuiltin(gfx_canvas));
    m.mapSet(Value(std::string("is_open")), Value::makeBuiltin(gfx_is_open));
    m.mapSet(Value(std::string("begin_draw")), Value::makeBuiltin(gfx_begin_draw));
    m.mapSet(Value(std::string("end_draw")), Value::makeBuiltin(gfx_end_draw));
    m.mapSet(Value(std::string("clear")), Value::makeBuiltin(gfx_clear));
    m.mapSet(Value(std::string("blendMode")), Value::makeBuiltin(gfx_blend_mode));
    m.mapSet(Value(std::string("strokeSize")), Value::makeBuiltin(gfx_stroke_size));
    m.mapSet(Value(std::string("stroke")), Value::makeBuiltin(gfx_stroke));
    m.mapSet(Value(std::string("noStroke")), Value::makeBuiltin(gfx_no_stroke));
    m.mapSet(Value(std::string("fill")), Value::makeBuiltin(gfx_fill));
    m.mapSet(Value(std::string("noFill")), Value::makeBuiltin(gfx_no_fill));
    m.mapSet(Value(std::string("tint")), Value::makeBuiltin(gfx_tint));
    m.mapSet(Value(std::string("noTint")), Value::makeBuiltin(gfx_no_tint));
    m.mapSet(Value(std::string("line")), Value::makeBuiltin(gfx_line));
    m.mapSet(Value(std::string("rect")), Value::makeBuiltin(gfx_rect));
    m.mapSet(Value(std::string("fps")), Value::makeBuiltin(gfx_fps));
    m.mapSet(Value(std::string("screenshot")), Value::makeBuiltin(gfx_screenshot));
    m.mapSet(Value(std::string("draw_text")), Value::makeBuiltin(gfx_draw_text));
    m.mapSet(Value(std::string("close")), Value::makeBuiltin(gfx_close));
    m.mapSet(Value(std::string("quit")), Value::makeBuiltin(gfx_quit));
    m.mapSet(Value(std::string("run")), Value::makeBuiltin(gfx_run));
    m.mapSet(Value(std::string("push")), Value::makeBuiltin(gfx_push));
    m.mapSet(Value(std::string("pop")), Value::makeBuiltin(gfx_pop));
    m.mapSet(Value(std::string("translate")), Value::makeBuiltin(gfx_translate));
    m.mapSet(Value(std::string("rotate")), Value::makeBuiltin(gfx_rotate));
    m.mapSet(Value(std::string("scale")), Value::makeBuiltin(gfx_scale));
    m.mapSet(Value(std::string("resetTransform")), Value::makeBuiltin(gfx_reset_transform));
    m.mapSet(Value(std::string("polygon")), Value::makeBuiltin(gfx_polygon));
    m.mapSet(Value(std::string("polyline")), Value::makeBuiltin(gfx_polyline));
    m.mapSet(Value(std::string("ellipse")), Value::makeBuiltin(gfx_ellipse));
    m.mapSet(Value(std::string("circle")), Value::makeBuiltin(gfx_circle));
    m.mapSet(Value(std::string("point")), Value::makeBuiltin(gfx_point));
    m.mapSet(Value(std::string("sprite")), Value::makeBuiltin(gfx_sprite));
    // Les constantes couleur ne sont PAS ici : utiliser le module `colors`.
    return m;
}
