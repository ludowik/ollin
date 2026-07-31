#include "graphics_internal.h"
#include "image_module.h"
#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include "keyboard_module.h"
#include "mouse_module.h"
#include <raylib.h>
#include <rlgl.h>
#include <raymath.h>
#include <cmath>
#include <stdexcept>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// gfxToInt : fourni en inline par graphics_internal.h (partagé 2D/3D).
// gfxToColor : déclaré dans graphics_internal.h, défini ici (lu aussi par graphics3d.cpp).
Color gfx_to_color(const Value& v) {
    if (!v.is_map() && !v.is_class())
        throw std::runtime_error("expected a Color object");
    auto get_comp = [&](const char* k, double def) -> uint8_t {
        Value f = v.map_get(Value(std::string(k)));
        return f.is_number() ? (uint8_t)(f.as_num() * 255.0 + 0.5) : (uint8_t)(def * 255.0 + 0.5);
    };
    return {get_comp("r", 0), get_comp("g", 0), get_comp("b", 0), get_comp("a", 1)};
}

// Composante [0,1] → octet [0,255] (bornée).
static uint8_t comp01(double v) {
    if (v < 0.0)
        v = 0.0;
    if (v > 1.0)
        v = 1.0;
    return (uint8_t)(v * 255.0 + 0.5);
}

static Color rgba_color(double r, double g, double b, double a) {
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
static void flush_pending_screenshot();   // défini plus bas (utilisé par gfx_end_draw)
// reset3dLightingState / reset3dGraphicsState / end3dInternal : déclarés dans graphics_internal.h (définis dans graphics3d.cpp)
// Un SEUL graphics.run par programme. Le moteur (runEntryHooks) appelle
// graphics.run(draw) automatiquement si draw() existe ; si le script l'appelle
// AUSSI explicitement, on aurait deux boucles → double CloseWindow (crash natif)
// ou double emscripten_set_main_loop (WASM). Ce garde-fou ignore le 2ᵉ appel.
// Remis à false dans gfx_canvas (début de programme) → re-run playground OK.
static bool s_run_active = false;

static int gfx_canvas(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    int w = argc > 0 ? gfx_to_int(args[0]) : 800;
    int h = argc > 1 ? gfx_to_int(args[1]) : 600;
    const char* title = (argc > 2 && args[2].is_string()) ? args[2].as_string().c_str() : "Ollin";
    s_shot_pending = false;   // nouveau programme → oublier une capture en attente
    s_blend_mode = BLEND_ALPHA;
    // Éclairage 3D remis à neuf ICI (avant que setup()/top-level ne pose ambient/
    // light) — et non dans gfx_run, qui s'exécute APRÈS et effacerait la config.
    reset3d_lighting_state();
    s_run_active = false;   // nouveau programme → autorise (un seul) graphics.run
#ifdef __EMSCRIPTEN__
    // RÉUTILISER le contexte WebGL entre deux runs (playground) au lieu de
    // CloseWindow + InitWindow. Chaque InitWindow (re)crée un contexte WebGL sur le
    // même canvas et recompile le shader par défaut de raylib ; à force de churn,
    // iOS PERD les contextes et le chargement de ce shader échoue dès la première
    // exécution suivante (« detachShader must be an instance of WebGLProgram »,
    // même en 2D — c'est le shader par défaut, pas le nôtre). On garde donc UN
    // seul contexte pour toute la session et on se contente de le redimensionner.
    bool reuse = IsWindowReady();
    if (reuse) {
        if (s_target_ready) {                 // libérer l'ancienne cible (contexte réutilisé → ids valides)
            UnloadRenderTexture(s_target);
            s_target_ready = false;
        }
        reset3d_graphics_state();               // libérer shader/meshes/textures/VBO 3D dans CE contexte
    }
    double dpr = EM_ASM_DOUBLE({ return window.device_pixel_ratio || 1.0; });
    s_physW = (int)(w * dpr + 0.5);
    s_physH = (int)(h * dpr + 0.5);
    // InitWindow with logical dimensions — sets projection [0,w]×[0,h]
    EM_ASM({
        var o = document.get_element_by_id('output');
        if (o)
            o.style.display = 'none';
    });
    if (reuse) {
        SetWindowSize(w, h);                   // même contexte WebGL, nouvelle taille logique
        SetWindowTitle(title);
    } else {
        SetConfigFlags(FLAG_MSAA_4X_HINT);
        InitWindow(w, h, title);
        SetTargetFPS(0);
    }
    // Override canvas bitmap to physical resolution, CSS display to logical size
    // rlViewport in emscripten_frame will render to the full physical bitmap
    EM_ASM(
        {
            var c = document.get_element_by_id('canvas');
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
    if (IsWindowReady()) {
        if (s_target_ready) {
            UnloadRenderTexture(s_target);
            s_target_ready = false;
        }
        reset3d_graphics_state();   // libérer les ressources GL 3D avant une éventuelle réinitialisation
    }
    s_physW = w;
    s_physH = h;
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    InitWindow(w, h, title);
    SetTargetFPS(60);
#endif
    s_logicalW = w;
    s_logicalH = h;
    // Repositionne les globales moteur sur la taille réelle du canvas : W/H aux
    // dimensions logiques, CW/CH au centre (float). Ainsi graphics.canvas(w, h)
    // recalcule W/H/CW/CH même quand w/h diffèrent des valeurs initiales window.
    if (VM* vm = VM::current()) {
        vm->set_global("W", Value((int64_t)w));
        vm->set_global("H", Value((int64_t)h));
        vm->set_global("CW", Value((double)w / 2.0));
        vm->set_global("CH", Value((double)h / 2.0));
    }
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
    Value win = VM::current()->get_global("window");
    if (win.is_map()) {
        win.map_set(Value(std::string("width")), Value((int64_t)w));
        win.map_set(Value(std::string("height")), Value((int64_t)h));
    }
    if (VM* vm = VM::current())
        vm->mark_gfx_canvas();   // canvas explicite → pas de canvas implicite (runEntryHooks)
    return ctx.ret(Value{});
}

static int gfx_is_open(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    return ctx.ret(Value(WindowShouldClose() ? int64_t(0) : int64_t(1)));
}

static int gfx_begin_draw(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    BeginDrawing();
    return ctx.ret(Value{});
}

static int gfx_end_draw(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    flush_pending_screenshot();   // chemin manuel beginDraw/endDraw : capture ici
    EndDrawing();
    return ctx.ret(Value{});
}

static int gfx_clear(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Color c = BLACK;
    if (argc > 0) {
        ColorRGBA k = parse_color(args, argc, "clear");
        c = rgba_color(k.r, k.g, k.b, k.a);
    }
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
    return ctx.ret(Value{});
}

// Mode de fusion des dessins suivants. Accepte une chaîne ("alpha", "add",
// "multiply", "subtract", "add_colors", "premultiply") ou une constante du
// module `blend`. Remis à "alpha" au début de chaque frame (resetStyles).
static int gfx_blend_mode(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    int mode = BLEND_ALPHA;
    if (argc > 0 && args[0].is_string()) {
        const std::string& s = args[0].as_string();
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
    } else if (argc > 0 && args[0].is_number()) {
        mode = (int)args[0].as_num();   // constante du module `blend`
    }
    s_blend_mode = mode;
    BeginBlendMode(mode);
    return ctx.ret(Value{});
}

// ── Style state ───────────────────────────────────────────────────────────────
static float s_stroke_size = 2.0f;
static bool s_has_stroke = true;
static Color s_stroke_color = WHITE;
static bool s_has_fill = false;
static Color s_fill_color = WHITE;
static int s_segments = 64;

static void apply_stroke_size(float sz) {
    s_stroke_size = sz;
}

// Trait sous-pixel : la RenderTexture n'a pas de MSAA → une épaisseur < 1 rend des
// pointillés (couverture partielle non lissée). On approxime l'anti-aliasing en
// gardant un trait CONTINU de 1px et en modulant l'alpha par la couverture
// (l'épaisseur) → trait fin, continu, de plus en plus pâle quand la taille baisse.
static void subpixel_stroke(float& w, Color& c) {
    if (w < 1.0f) {
        float cov = w < 0.0f ? 0.0f : w;
        c.a = (unsigned char)(c.a * cov + 0.5f);
        w = 1.0f;
    }
}

// Épaisseur + couleur de contour courantes, ajustées pour le rendu sous-pixel.
struct StrokeWC {
    float w;
    Color c;
};
static StrokeWC stroke_params() {
    float w = s_stroke_size;
    Color c = s_stroke_color;
    subpixel_stroke(w, c);
    return {w, c};
}
static void apply_stroke(bool en, Color c = WHITE) {
    s_has_stroke = en;
    s_stroke_color = c;
}
static void apply_fill(bool en, Color c = WHITE) {
    s_has_fill = en;
    s_fill_color = c;
}

// Accesseurs d'état de style (déclarés dans graphics_internal.h) — lus par graphics3d.cpp.
bool gfx_has_fill() {
    return s_has_fill;
}
Color gfx_fill_color() {
    return s_fill_color;
}
bool gfx_has_stroke() {
    return s_has_stroke;
}
Color gfx_stroke_color() {
    return s_stroke_color;
}
float gfx_stroke_size() {
    return s_stroke_size;
}
int gfx_segments() {
    return s_segments;
}

// ── Contextes de style (pile) ───────────────────────────────────────────────
// Capture/restaure TOUT l'état de dessin : trait, remplissage, mode de fusion,
// teinte d'image (image_module) et texture 3D courante (graphics3d). Utilisé par
// push/pop (matrice + style) et pushStyle/popStyle (style seul).
struct StyleState {
    float stroke_size;
    bool  has_stroke;
    Color stroke_color;
    bool  has_fill;
    Color fill_color;
    int   blendMode;
    bool  has_tint;
    Color tint;
    unsigned int tex3d;
    int   segments;
};
static std::vector<StyleState> s_style_stack;

static StyleState capture_style() {
    StyleState s;
    s.stroke_size = s_stroke_size;
    s.has_stroke = s_has_stroke;
    s.stroke_color = s_stroke_color;
    s.has_fill = s_has_fill;
    s.fill_color = s_fill_color;
    s.blendMode = s_blend_mode;
    image_get_tint(&s.has_tint, &s.tint.r, &s.tint.g, &s.tint.b, &s.tint.a);
    s.tex3d = gfx3d_get_texture();
    s.segments = s_segments;
    return s;
}

static void restore_style(const StyleState& s) {
    s_stroke_size = s.stroke_size;
    s_has_stroke = s.has_stroke;
    s_stroke_color = s.stroke_color;
    s_has_fill = s.has_fill;
    s_fill_color = s.fill_color;
    s_blend_mode = s.blendMode;
    BeginBlendMode(s.blendMode);
    image_set_tint(s.has_tint, s.tint.r, s.tint.g, s.tint.b, s.tint.a);
    gfx3d_set_texture(s.tex3d);
    s_segments = s.segments;
}

static void reset_styles() {
    apply_stroke_size(2.0f);
    apply_stroke(true, WHITE);
    apply_fill(false);
    image_set_tint(false, 255, 255, 255, 255);   // pas de teinte par défaut (comme fill/stroke, remis chaque frame)
    s_blend_mode = BLEND_ALPHA;                   // mode de fusion remis par défaut chaque frame
    reset3d_frame_state();                          // texture 3D remise à « aucune » (blanche) chaque frame
    s_style_stack.clear();                        // pile de style repartie à neuf chaque frame (push/pop équilibrés dans draw)
    BeginBlendMode(BLEND_ALPHA);
    rlLoadIdentity();
}

static int gfx_stroke_size(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].is_number())
        apply_stroke_size((float)args[0].as_num());
    return ctx.ret(Value{});
}

static int gfx_segments(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].is_number())
        s_segments = std::max(3, (int)args[0].as_num());
    return ctx.ret(Value{});
}

static int gfx_stroke(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0) {
        s_has_stroke = true;                   // sans argument → (ré)active avec la couleur courante
        return ctx.ret(Value{});
    }
    ColorRGBA k = parse_color(args, argc, "stroke");
    apply_stroke(true, rgba_color(k.r, k.g, k.b, k.a));
    // Taille optionnelle : seulement avec un objet Color en 1er arg — stroke(Color, taille).
    // (Pour les formes numériques, utiliser graphics.strokeSize : les nombres = couleur.)
    if ((args[0].is_map() || args[0].is_class()) && argc > 1 && args[1].is_number())
        apply_stroke_size((float)args[1].as_num());
    return ctx.ret(Value{});
}

static int gfx_no_stroke(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_has_stroke = false;                       // ne plus dessiner de contour (couleur conservée)
    return ctx.ret(Value{});
}

static int gfx_fill(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0) {
        s_has_fill = true;                   // sans argument → (ré)active avec la couleur courante
        return ctx.ret(Value{});
    }
    ColorRGBA k = parse_color(args, argc, "fill");
    apply_fill(true, rgba_color(k.r, k.g, k.b, k.a));
    return ctx.ret(Value{});
}

static int gfx_no_fill(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_has_fill = false;                       // ne plus remplir (couleur conservée)
    return ctx.ret(Value{});
}

// Teinte globale des images (graphics.sprite / image.draw) : objet Color ou r,g,b[,a].
static int gfx_tint(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0)
        return ctx.ret(Value{});   // sans argument : ne change rien
    ColorRGBA k = parse_color(args, argc, "tint");   // même signature que clear/fill/stroke
    Color c = rgba_color(k.r, k.g, k.b, k.a);
    image_set_tint(true, c.r, c.g, c.b, c.a);
    return ctx.ret(Value{});
}

static int gfx_no_tint(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    image_set_tint(false, 255, 255, 255, 255);
    return ctx.ret(Value{});
}

static int gfx_line(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 4)
        throw std::runtime_error("graphics.line: expected x1, y1, x2, y2");
    if (!s_has_stroke)
        return ctx.ret(Value{});
    float x1 = (float)num_arg(args, 0, "graphics.line");
    float y1 = (float)num_arg(args, 1, "graphics.line");
    float x2 = (float)num_arg(args, 2, "graphics.line");
    float y2 = (float)num_arg(args, 3, "graphics.line");
    StrokeWC s = stroke_params();   // trait fin continu (< 1 → alpha modulé) au lieu de pointillés
    DrawLineEx({x1, y1}, {x2, y2}, s.w, s.c);
    return ctx.ret(Value{});
}

static int gfx_rect(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 4)
        throw std::runtime_error("graphics.rect: expected x, y, w, h");
    int x = gfx_to_int(args[0]);
    int y = gfx_to_int(args[1]);
    int w = gfx_to_int(args[2]);
    int h = gfx_to_int(args[3]);
    if (s_has_fill)
        DrawRectangle(x, y, w, h, s_fill_color);
    if (s_has_stroke) {
        StrokeWC s = stroke_params();
        DrawRectangleLinesEx({(float)x, (float)y, (float)w, (float)h}, s.w, s.c);
    }
    return ctx.ret(Value{});
}

static int gfx_fps(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    return ctx.ret(Value((int64_t)GetFPS()));
}

// Capture le framebuffer AFFICHÉ dans un PNG. Comme draw() rend dans la
// RenderTexture persistante (liée pendant draw), on ne peut pas capturer l'écran
// composité ici : on DIFFÈRE la capture à la fin de la frame (après composition),
// dans renderFrame (ou dans gfx_end_draw pour le chemin manuel). Sur WASM,
// TakeScreenshot déclenche un téléchargement. (s_shot_path/s_shot_pending : voir haut.)
static int gfx_screenshot(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("graphics.screenshot: expected a file path");
    s_shot_path = args[0].as_string();
    s_shot_pending = true;
    return ctx.ret(Value{});
}

// Exécute une capture en attente : appelé en fin de frame par renderFrame, quand
// le framebuffer par défaut contient l'image composée (écran réellement affiché).
static void flush_pending_screenshot() {
    if (!s_shot_pending)
        return;
    s_shot_pending = false;
    rlDrawRenderBatchActive();
    TakeScreenshot(s_shot_path.c_str());
}

static int gfx_text(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 4)
        throw std::runtime_error("graphics.text: expected text, x, y, size [, color]");
    const char* text = args[0].is_string() ? args[0].as_string().c_str() : "";
    DrawText(text, gfx_to_int(args[1]), gfx_to_int(args[2]), gfx_to_int(args[3]), argc > 4 ? gfx_to_color(args[4]) : s_stroke_color);
    return ctx.ret(Value{});
}

static int gfx_close(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    CloseWindow();
    return ctx.ret(Value{});
}

// ── Polygon ───────────────────────────────────────────────────────────────────
static void poly_fill(std::vector<Vector2> pts, Color color) {
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

static std::vector<Vector2> parse_points(const Value& v, const char* fn) {
    std::vector<Vector2> pts;
    if (!v.is_array())
        return pts;
    const auto& items = v.aptr->items;
    if (items.empty())
        return pts;
    auto req = [&](const Value& c) -> float {
        if (!c.is_number())
            throw std::runtime_error(std::string(fn) + ": les coordonnées de point doivent être des nombres");
        return (float)c.as_num();
    };
    if (items[0].is_array()) {
        for (const auto& p : items) {
            if (!p.is_array() || p.aptr->items.size() < 2)
                continue;
            pts.push_back({req(p.aptr->items[0]), req(p.aptr->items[1])});
        }
    } else {
        for (size_t i = 0; i + 1 < items.size(); i += 2)
            pts.push_back({req(items[i]), req(items[i + 1])});
    }
    return pts;
}

// Tracé d'une polyligne épaisse avec JOINTURES/EMBOUTS ARRONDIS. À forte épaisseur,
// des DrawLineEx indépendants laissent des encoches aux sommets (coins non jointés,
// aspect « roue dentée »). Un disque de rayon épaisseur/2 posé sur chaque sommet
// comble le creux extérieur et donne une jointure ronde (embouts ronds aux extrémités
// d'une polyligne ouverte). Négligeable en dessous de ~2px → sauté (perf, sans effet).
static void draw_thick_path(const std::vector<Vector2>& pts, bool closed, float w, Color c) {
    int n = (int)pts.size();
    if (n < 2)
        return;
    int segs = closed ? n : n - 1;
    for (int i = 0; i < segs; i++)
        DrawLineEx(pts[i], pts[(i + 1) % n], w, c);
    if (w > 2.0f) {
        float r = w * 0.5f;
        for (int i = 0; i < n; i++)
            DrawCircleV(pts[i], r, c);
    }
}

static int gfx_polygon(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "graphics.polygon";
    if (argc < 1 || !args[0].is_array())
        throw std::runtime_error(std::string(FN) + ": expected array of points");
    auto pts = parse_points(args[0], FN);
    if ((int)pts.size() < 3)
        return ctx.ret(Value{});
    if (s_has_fill)
        poly_fill(pts, s_fill_color);
    if (s_has_stroke) {
        StrokeWC s = stroke_params();
        draw_thick_path(pts, true, s.w, s.c);
    }
    return ctx.ret(Value{});
}

static int gfx_polyline(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "graphics.polyline";
    if (argc < 1 || !args[0].is_array())
        throw std::runtime_error(std::string(FN) + ": expected array of points");
    if (!s_has_stroke)
        return ctx.ret(Value{});
    auto pts = parse_points(args[0], FN);
    StrokeWC s = stroke_params();
    draw_thick_path(pts, false, s.w, s.c);
    return ctx.ret(Value{});
}

// Contour épais d'une ellipse = anneau triangulé entre un contour INTÉRIEUR
// (r - épaisseur/2) et EXTÉRIEUR (r + épaisseur/2), l'épaisseur étant centrée sur
// le tracé (sémantique p5.js). Auparavant on dessinait `segs` segments épais
// (DrawLineEx) : à forte épaisseur, leurs coins non jointés dépassaient et
// donnaient un aspect « roue dentée » (pointes). L'anneau, lui, reste lisse.
static void draw_ellipse_stroke(float cx, float cy, float rx, float ry, float thick, Color color, int segs) {
    float h = thick * 0.5f;
    float rxi = rx - h;
    float ryi = ry - h;
    if (rxi < 0.0f) {
        rxi = 0.0f;
    }
    if (ryi < 0.0f) {
        ryi = 0.0f;
    }
    float rxo = rx + h;
    float ryo = ry + h;
    for (int i = 0; i < segs; i++) {
        float a0 = (float)i / segs * 2.0f * PI;
        float a1 = (float)(i + 1) / segs * 2.0f * PI;
        float c0 = cosf(a0);
        float s0 = sinf(a0);
        float c1 = cosf(a1);
        float s1 = sinf(a1);
        Vector2 o0 = {cx + rxo * c0, cy + ryo * s0};
        Vector2 o1 = {cx + rxo * c1, cy + ryo * s1};
        Vector2 i0 = {cx + rxi * c0, cy + ryi * s0};
        Vector2 i1 = {cx + rxi * c1, cy + ryi * s1};
        // Quad (o0,o1,i1,i0) → 2 triangles, même sens que drawEllipseFill.
        DrawTriangle(o0, o1, i1, color);
        DrawTriangle(o0, i1, i0, color);
    }
}

static void draw_ellipse_fill(float cx, float cy, float rx, float ry, Color color, int segs) {
    for (int i = 0; i < segs; i++) {
        float a0 = (float)i / segs * 2.0f * PI;
        float a1 = (float)(i + 1) / segs * 2.0f * PI;
        DrawTriangle({cx, cy}, {cx + rx * cosf(a1), cy + ry * sinf(a1)}, {cx + rx * cosf(a0), cy + ry * sinf(a0)},
                     color);
    }
}

static void draw_oval(float cx, float cy, float rx, float ry, int segs) {
    if (s_has_fill)
        draw_ellipse_fill(cx, cy, rx, ry, s_fill_color, segs);
    if (s_has_stroke) {
        StrokeWC s = stroke_params();
        if (rx == ry) {
            // Cercle : anneau natif raylib (contour lisse, épaisseur centrée sur r).
            float inner = rx - s.w * 0.5f;
            if (inner < 0.0f) {
                inner = 0.0f;
            }
            DrawRing({cx, cy}, inner, rx + s.w * 0.5f, 0.0f, 360.0f, segs, s.c);
        } else {
            draw_ellipse_stroke(cx, cy, rx, ry, s.w, s.c, segs);
        }
    }
}

static int gfx_ellipse(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 4)
        throw std::runtime_error("graphics.ellipse: expected x, y, width, height");
    int segs = (argc > 4 && args[4].is_number()) ? std::max(3, (int)args[4].as_num()) : s_segments;
    draw_oval((float)num_arg(args, 0, "graphics.ellipse"), (float)num_arg(args, 1, "graphics.ellipse"),
             (float)num_arg(args, 2, "graphics.ellipse") * 0.5f, (float)num_arg(args, 3, "graphics.ellipse") * 0.5f, segs);
    return ctx.ret(Value{});
}

static int gfx_circle(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("graphics.circle: expected x, y, radius");
    int segs = (argc > 3 && args[3].is_number()) ? std::max(3, (int)args[3].as_num()) : s_segments;
    float r = (float)num_arg(args, 2, "graphics.circle");
    draw_oval((float)num_arg(args, 0, "graphics.circle"), (float)num_arg(args, 1, "graphics.circle"), r, r, segs);
    return ctx.ret(Value{});
}

// Secteur (part de tarte) : triangles depuis le centre sur l'arc [start;stop].
static void draw_arc_fill(float cx, float cy, float rx, float ry, float start, float stop, Color color, int segs) {
    for (int i = 0; i < segs; i++) {
        float a0 = start + (stop - start) * (float)i / segs;
        float a1 = start + (stop - start) * (float)(i + 1) / segs;
        DrawTriangle({cx, cy}, {cx + rx * cosf(a1), cy + ry * sinf(a1)}, {cx + rx * cosf(a0), cy + ry * sinf(a0)},
                     color);
    }
}

// Contour de l'arc SEUL (courbe, sans les rayons) : anneau triangulé sur [start;stop],
// épaisseur centrée sur le tracé — même construction que drawEllipseStroke.
static void draw_arc_stroke(float cx, float cy, float rx, float ry, float start, float stop, float thick, Color color,
                          int segs) {
    float h = thick * 0.5f;
    float rxi = rx - h;
    float ryi = ry - h;
    if (rxi < 0.0f) {
        rxi = 0.0f;
    }
    if (ryi < 0.0f) {
        ryi = 0.0f;
    }
    float rxo = rx + h;
    float ryo = ry + h;
    for (int i = 0; i < segs; i++) {
        float a0 = start + (stop - start) * (float)i / segs;
        float a1 = start + (stop - start) * (float)(i + 1) / segs;
        float c0 = cosf(a0);
        float s0 = sinf(a0);
        float c1 = cosf(a1);
        float s1 = sinf(a1);
        Vector2 o0 = {cx + rxo * c0, cy + ryo * s0};
        Vector2 o1 = {cx + rxo * c1, cy + ryo * s1};
        Vector2 i0 = {cx + rxi * c0, cy + ryi * s0};
        Vector2 i1 = {cx + rxi * c1, cy + ryi * s1};
        // Winding aligné sur drawArcFill (front-face, sinon back-face-culled → invisible).
        DrawTriangle(o0, i1, o1, color);
        DrawTriangle(o0, i0, i1, color);
    }
}

// arc(x, y, w, h, start, stop) : arc elliptique. w/h = tailles pleines (comme ellipse).
// start/stop en radians, sens horaire (y vers le bas → angle croissant = horaire).
// fill → secteur plein ; stroke → courbe de l'arc seule. segs proportionnel à l'angle.
static int gfx_arc(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "graphics.arc";
    if (argc < 6)
        throw std::runtime_error(std::string(FN) + ": expected x, y, w, h, start, stop");
    float cx = (float)num_arg(args, 0, FN);
    float cy = (float)num_arg(args, 1, FN);
    float rx = (float)num_arg(args, 2, FN) * 0.5f;
    float ry = (float)num_arg(args, 3, FN) * 0.5f;
    float start = (float)num_arg(args, 4, FN);
    float stop = (float)num_arg(args, 5, FN);
    while (stop < start) {
        stop += 2.0f * PI;
    }
    float span = stop - start;
    if (span > 2.0f * PI) {
        span = 2.0f * PI;
        stop = start + span;
    }
    int segs = (int)ceilf((float)s_segments * span / (2.0f * PI));
    if (segs < 2) {
        segs = 2;
    }
    if (s_has_fill)
        draw_arc_fill(cx, cy, rx, ry, start, stop, s_fill_color, segs);
    if (s_has_stroke) {
        StrokeWC s = stroke_params();
        draw_arc_stroke(cx, cy, rx, ry, start, stop, s.w, s.c, segs);
    }
    return ctx.ret(Value{});
}

static int gfx_point(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 2)
        throw std::runtime_error("graphics.point: expected x, y");
    if (!s_has_stroke)
        return ctx.ret(Value{});
    float x = (float)num_arg(args, 0, "graphics.point");
    float y = (float)num_arg(args, 1, "graphics.point");
    DrawCircleV({x, y}, s_stroke_size, s_stroke_color);
    return ctx.ret(Value{});
}

#ifndef __EMSCRIPTEN__
static bool s_quit = false; // boucle native seulement (WASM : emscripten_cancel_main_loop)
#endif

// Delta de frame mesuré NOUS-MÊMES : horloge murale (GetTime()) lue à un point
// UNIQUE par frame (entrée de renderFrame). On n'utilise PAS GetFrameTime()/
// GetFPS() de raylib : dans notre boucle web (1 requestAnimationFrame par frame,
// dessin dans une RenderTexture persistante), leur mesure frame = update + draw
// ne compte pas l'attente rAF ENTRE deux frames → dt sous-évalué. Conséquences :
// deltaTime trop petit (simulation au ralenti) et FPS sur-évalué (76 affiché
// pour 60 réels). L'écart mur entre deux entrées de frame, lui, est exact.
static double s_frame_dt = 0.0;          // durée de la dernière frame (secondes)
static double s_last_frame_time = -1.0;  // horodatage de la frame précédente
static double s_fps_ema = 0.0;           // FPS lissé (moyenne exponentielle)

// Overlay FPS dessiné par le moteur après chaque frame (toujours en haut à
// droite de la zone graphique). Couleur vive + ombre → lisible sur tout fond.
static void draw_fps_overlay() {
    // FPS calculé depuis NOTRE delta (fiable), lissé pour éviter le scintillement.
    if (s_frame_dt > 0.0) {
        double inst = 1.0 / s_frame_dt;
        s_fps_ema = (s_fps_ema <= 0.0) ? inst : (s_fps_ema * 0.9 + inst * 0.1);
    }
    int fps = (int)(s_fps_ema + 0.5);
    // Mémoire utilisée à côté du FPS (Ko sous 1 Mo, sinon Mo).
    double kb = ollin_heap_bytes() / 1024.0;
    const char* buf = (kb >= 1024.0) ? TextFormat("%.1f Mo  %d fps", kb / 1024.0, fps)
                                     : TextFormat("%.0f Ko  %d fps", kb, fps);
    const int size = 16, margin = 8;
    int tw = MeasureText(buf, size);
    int x = s_logicalW - tw - margin;
    int y = margin;
    DrawText(buf, x + 1, y + 1, size, BLACK);     // ombre (contraste)
    DrawText(buf, x, y, size, {0, 228, 48, 255}); // vert vif (lime)
}

static int gfx_quit(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
#ifdef __EMSCRIPTEN__
    emscripten_cancel_main_loop();
#else
    s_quit = true;
#endif
    return ctx.ret(Value{});
}

// Temps accumulé depuis le démarrage du programme (remis à 0 à chaque gfx_run).
static double s_elapsed_time = 0.0;

// Met à jour deltaTime/elapsedTime dans la VM et appelle update(dt) si définie.
static Value s_update_callback;
static void call_update_if_any() {
    double dt = s_frame_dt;   // notre mesure fiable, pas GetFrameTime() (cf. plus haut)
    s_elapsed_time += dt;
    VM* vm = VM::current();
    vm->set_global("deltaTime", Value(dt));
    vm->set_global("elapsedTime", Value(s_elapsed_time));
    if (s_update_callback.is_callable())
        vm->call_value(s_update_callback, Value(dt));
}

// Rend UNE frame. Le contexte n'est PAS effacé d'office : draw() dessine dans la
// cible persistante s_target (c'est à draw() d'appeler graphics.clear() s'il veut
// repartir d'un fond net), puis on ré-affiche s_target à l'écran et on pose
// l'overlay FPS PAR-DESSUS (donc net, jamais accumulé). `tex`/`drawing` renvoient
// l'état des blocs ouverts pour un nettoyage sûr si draw() lève (boucle web).
// Prélude commun d'une frame : styles par défaut, entrées, logique (update),
// puis rendu utilisateur (draw). Partagé par les deux chemins de renderFrame.
static void run_user_callbacks(const Value& draw_fn) {
    reset_styles();
    keyboard_poll();
    mouse_poll();
    call_update_if_any();
    VM::current()->call_value(const_cast<Value&>(draw_fn));
    end3d_internal();   // no-op hors 3D ; sinon flush + refermer si draw() a oublié end3d
}

static void render_frame(const Value& draw_fn, bool* tex, bool* drawing) {
    *tex = false;
    *drawing = false;
    // Delta de frame : écart mur depuis l'entrée de la frame précédente (inclut
    // l'attente rAF, contrairement à GetFrameTime). Première frame → dt = 0.
    double now = GetTime();
    s_frame_dt = (s_last_frame_time < 0.0) ? 0.0 : (now - s_last_frame_time);
    s_last_frame_time = now;
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
        run_user_callbacks(draw_fn);
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
        flush_pending_screenshot();      // capture l'écran composé (avant l'overlay FPS)
        BeginBlendMode(BLEND_ALPHA);   // overlay FPS en fusion normale
        draw_fps_overlay();
        *drawing = false;
        EndDrawing();
    } else {
        // Repli : aucun canvas persistant configuré → rendu direct (ancien comportement).
        BeginDrawing();
        *drawing = true;
        if (s_physW != GetScreenWidth() || s_physH != GetScreenHeight())
            rlViewport(0, 0, s_physW, s_physH);
        run_user_callbacks(draw_fn);
        flush_pending_screenshot();      // capture l'écran (avant l'overlay FPS)
        draw_fps_overlay();
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
        render_frame(s_run_callback, &tex, &drawing);
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

static int gfx_run(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.run: expected callback function");
    if (s_run_active)   // déjà lancé pour ce programme → ignorer le 2ᵉ appel (voir s_run_active)
        return ctx.ret(Value{});
    s_run_active = true;
    Value fn = args[0];
    s_elapsed_time = 0.0;
    s_last_frame_time = -1.0;   // 1re frame → dt = 0 (pas de saut initial)
    s_fps_ema = 0.0;
    keyboard_reset();            // état clavier neuf (s_down statique persiste entre runs WASM)
    s_update_callback = VM::current()->get_global("update");
#ifdef __EMSCRIPTEN__
    s_run_callback = fn;
    emscripten_set_main_loop(emscripten_frame, 0, 0);
#else
    s_quit = false;
    while (!WindowShouldClose() && !s_quit) {
        bool tex = false, drawing = false;
        render_frame(fn, &tex, &drawing);
    }
    if (s_target_ready) {
        UnloadRenderTexture(s_target);
        s_target_ready = false;
    }
    CloseWindow();
#endif
    return ctx.ret(Value{});
}

// ── Transformations matricielles + contextes de style ──────────────────────────
// push/pop        : sauvent/restaurent À LA FOIS la matrice ET le style (Processing/p5).
// pushMatrix/pop  : matrice seule.  pushStyle/pop : style seul.
static int gfx_push(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    rlPushMatrix();
    s_style_stack.push_back(capture_style());
    return ctx.ret(Value{});
}

static int gfx_pop(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    if (!s_style_stack.empty()) {
        restore_style(s_style_stack.back());
        s_style_stack.pop_back();
    }
    rlPopMatrix();
    return ctx.ret(Value{});
}

static int gfx_push_matrix(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    rlPushMatrix();
    return ctx.ret(Value{});
}

static int gfx_pop_matrix(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    rlPopMatrix();
    return ctx.ret(Value{});
}

static int gfx_push_style(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_style_stack.push_back(capture_style());
    return ctx.ret(Value{});
}

static int gfx_pop_style(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    if (!s_style_stack.empty()) {
        restore_style(s_style_stack.back());
        s_style_stack.pop_back();
    }
    return ctx.ret(Value{});
}

// graphics.translate(x, y [, z]) : z optionnel (défaut 0) → 2D et 3D.
static int gfx_translate(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 2)
        throw std::runtime_error("graphics.translate: expected x, y [, z]");
    float x = (float)num_arg(args, 0, "graphics.translate");
    float y = (float)num_arg(args, 1, "graphics.translate");
    float z = argc > 2 ? (float)num_arg(args, 2, "graphics.translate") : 0.0f;
    rlTranslatef(x, y, z);
    return ctx.ret(Value{});
}

// Rotation de deg° (argument 0) autour de l'axe (ax,ay,az) — facteur commun de
// rotate (axe Z par défaut) et de rotateX/rotateY/rotateZ.
static void rotate_axis(Value* args, int argc, float ax, float ay, float az, const char* fn) {
    rlRotatef((float)num_arg(args, argc, 0, fn), ax, ay, az);
}

// graphics.rotate(deg [, ax, ay, az]) : sans axe → autour de Z ; avec les 3
// composantes → rotation 3D autour de (ax,ay,az). Un axe PARTIEL (2 ou 3 args)
// est une ERREUR — on ne retombe pas silencieusement sur Z.
static int gfx_rotate(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 1) {
        rotate_axis(args, argc, 0.0f, 0.0f, 1.0f, "graphics.rotate");   // axe Z par défaut
    } else if (argc >= 4) {
        rlRotatef((float)num_arg(args, argc, 0, "graphics.rotate"), (float)num_arg(args, argc, 1, "graphics.rotate"),
                  (float)num_arg(args, argc, 2, "graphics.rotate"), (float)num_arg(args, argc, 3, "graphics.rotate"));
    } else {
        throw std::runtime_error("graphics.rotate: expected deg [, ax, ay, az] (axe complet ou aucun)");
    }
    return ctx.ret(Value{});
}

static int gfx_rotate_x(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    rotate_axis(args, argc, 1.0f, 0.0f, 0.0f, "graphics.rotateX");
    return ctx.ret(Value{});
}
static int gfx_rotate_y(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    rotate_axis(args, argc, 0.0f, 1.0f, 0.0f, "graphics.rotateY");
    return ctx.ret(Value{});
}
static int gfx_rotate_z(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    rotate_axis(args, argc, 0.0f, 0.0f, 1.0f, "graphics.rotateZ");
    return ctx.ret(Value{});
}

// graphics.scale(s | sx,sy | sx,sy,sz) : 1 arg = uniforme (s,s,s) ; 2 args =
// (sx,sy,1) (2D) ; 3 args = (sx,sy,sz).
static int gfx_scale(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.scale: expected s | sx, sy | sx, sy, sz");
    float sx = (float)num_arg(args, 0, "graphics.scale");
    float sy, sz;
    if (argc >= 3) {
        sy = (float)num_arg(args, 1, "graphics.scale");
        sz = (float)num_arg(args, 2, "graphics.scale");
    } else if (argc == 2) {
        sy = (float)num_arg(args, 1, "graphics.scale");
        sz = 1.0f;
    } else {
        sy = sx;   // uniforme sur les 3 axes
        sz = sx;
    }
    rlScalef(sx, sy, sz);
    return ctx.ret(Value{});
}

static int gfx_reset_transform(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    rlLoadIdentity();
    return ctx.ret(Value{});
}

// ── graphics.sprite(img, x, y [, w, h]) ──────────────────────────────────────

static int gfx_sprite(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("graphics.sprite: expected img, x, y");
    if (!args[0].is_map())
        throw std::runtime_error("graphics.sprite: expected image handle");
    Value idv = args[0].map_get(Value(std::string("id")));
    if (!idv.is_integer())
        throw std::runtime_error("graphics.sprite: invalid image handle");
    int id = (int)idv.as_int();

    float x = (float)num_arg(args, 1, "graphics.sprite");
    float y = (float)num_arg(args, 2, "graphics.sprite");
    float dw = argc > 3 ? (float)num_arg(args, 3, "graphics.sprite") : 0.0f;
    float dh = argc > 4 ? (float)num_arg(args, 4, "graphics.sprite") : 0.0f;

    bool has = false;
    unsigned char r = 255, g = 255, b = 255, a = 255;
    image_get_tint(&has, &r, &g, &b, &a);
    image_draw_sprite(id, x, y, dw, dh, r, g, b, a);
    return ctx.ret(Value{});
}


// Module `blend` : modes de fusion exposés via les enums raylib DIRECTEMENT
// (source de vérité — pas de littéraux à maintenir/vérifier). Défini ici plutôt
// que dans modules.cpp car ce dernier compile aussi sans raylib.
Value make_blend_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("ALPHA")), Value((int64_t)BLEND_ALPHA));
    m.map_set(Value(std::string("ADD")), Value((int64_t)BLEND_ADDITIVE));
    m.map_set(Value(std::string("MULTIPLY")), Value((int64_t)BLEND_MULTIPLIED));
    m.map_set(Value(std::string("ADD_COLORS")), Value((int64_t)BLEND_ADD_COLORS));
    m.map_set(Value(std::string("SUBTRACT")), Value((int64_t)BLEND_SUBTRACT_COLORS));
    m.map_set(Value(std::string("PREMULTIPLY")), Value((int64_t)BLEND_ALPHA_PREMULTIPLY));
    return m;
}

Value make_graphics_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("canvas")), Value::make_builtin(gfx_canvas));
    m.map_set(Value(std::string("isOpen")), Value::make_builtin(gfx_is_open));
    m.map_set(Value(std::string("beginDraw")), Value::make_builtin(gfx_begin_draw));
    m.map_set(Value(std::string("endDraw")), Value::make_builtin(gfx_end_draw));
    m.map_set(Value(std::string("clear")), Value::make_builtin(gfx_clear));
    m.map_set(Value(std::string("blendMode")), Value::make_builtin(gfx_blend_mode));
    m.map_set(Value(std::string("strokeSize")), Value::make_builtin(gfx_stroke_size));
    m.map_set(Value(std::string("segments")), Value::make_builtin(gfx_segments));
    m.map_set(Value(std::string("stroke")), Value::make_builtin(gfx_stroke));
    m.map_set(Value(std::string("noStroke")), Value::make_builtin(gfx_no_stroke));
    m.map_set(Value(std::string("fill")), Value::make_builtin(gfx_fill));
    m.map_set(Value(std::string("noFill")), Value::make_builtin(gfx_no_fill));
    m.map_set(Value(std::string("tint")), Value::make_builtin(gfx_tint));
    m.map_set(Value(std::string("noTint")), Value::make_builtin(gfx_no_tint));
    m.map_set(Value(std::string("line")), Value::make_builtin(gfx_line));
    m.map_set(Value(std::string("rect")), Value::make_builtin(gfx_rect));
    m.map_set(Value(std::string("fps")), Value::make_builtin(gfx_fps));
    m.map_set(Value(std::string("screenshot")), Value::make_builtin(gfx_screenshot));
    m.map_set(Value(std::string("text")), Value::make_builtin(gfx_text));
    m.map_set(Value(std::string("close")), Value::make_builtin(gfx_close));
    m.map_set(Value(std::string("quit")), Value::make_builtin(gfx_quit));
    m.map_set(Value(std::string("run")), Value::make_builtin(gfx_run));
    m.map_set(Value(std::string("push")), Value::make_builtin(gfx_push));
    m.map_set(Value(std::string("pop")), Value::make_builtin(gfx_pop));
    m.map_set(Value(std::string("pushMatrix")), Value::make_builtin(gfx_push_matrix));
    m.map_set(Value(std::string("popMatrix")), Value::make_builtin(gfx_pop_matrix));
    m.map_set(Value(std::string("pushStyle")), Value::make_builtin(gfx_push_style));
    m.map_set(Value(std::string("popStyle")), Value::make_builtin(gfx_pop_style));
    m.map_set(Value(std::string("translate")), Value::make_builtin(gfx_translate));
    m.map_set(Value(std::string("rotate")), Value::make_builtin(gfx_rotate));
    m.map_set(Value(std::string("rotateX")), Value::make_builtin(gfx_rotate_x));
    m.map_set(Value(std::string("rotateY")), Value::make_builtin(gfx_rotate_y));
    m.map_set(Value(std::string("rotateZ")), Value::make_builtin(gfx_rotate_z));
    m.map_set(Value(std::string("scale")), Value::make_builtin(gfx_scale));
    m.map_set(Value(std::string("resetTransform")), Value::make_builtin(gfx_reset_transform));
    m.map_set(Value(std::string("polygon")), Value::make_builtin(gfx_polygon));
    m.map_set(Value(std::string("polyline")), Value::make_builtin(gfx_polyline));
    m.map_set(Value(std::string("ellipse")), Value::make_builtin(gfx_ellipse));
    m.map_set(Value(std::string("circle")), Value::make_builtin(gfx_circle));
    m.map_set(Value(std::string("arc")), Value::make_builtin(gfx_arc));
    m.map_set(Value(std::string("point")), Value::make_builtin(gfx_point));
    m.map_set(Value(std::string("sprite")), Value::make_builtin(gfx_sprite));
    register3d_graphics(m);   // 3D (caméra, begin3d/end3d, primitives, éclairage, texture) — graphics3d.cpp
    // Les constantes couleur ne sont PAS ici : utiliser le module `colors`.
    return m;
}
