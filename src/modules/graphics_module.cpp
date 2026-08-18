#include "graphics_internal.h"
#include "ui_module.h"
#include "tween_module.h"
#include "engine_font.h"
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
static int s_logicalW = 0; // largeur logique de la zone (pour l'overlay mémoire/FPS)
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
static void gfx_reset_capture();          // idem (utilisé par gfx_canvas)
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
    gfx_reset_capture();      // idem pour la capture demandée par l'hôte
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
    double dpr = EM_ASM_DOUBLE({ return window.devicePixelRatio || 1.0; });
    s_physW = (int)(w * dpr + 0.5);
    s_physH = (int)(h * dpr + 0.5);
    // InitWindow with logical dimensions — sets projection [0,w]×[0,h]
    EM_ASM({
        var o = document.getElementById('output');
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
    return ctx.ret(Value::make_bool(!WindowShouldClose()));
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
static float s_font_size = 18.0f;   // taille de police (état), comme s_stroke_size
// Police courante, index dans le registre du moteur (engine_font.h) : un ÉTAT de style
// comme la taille, donc sauvegardé par push/pushStyle et remis au défaut chaque frame.
static int s_font_idx = engine_font_default();
// Ancrage de rect : x,y = coin supérieur gauche (défaut) ou centre. C'est un ÉTAT,
// comme blendMode : cela ne change pas la géométrie mais son interprétation.
static const int RECT_CORNER = 0;
static const int RECT_CENTER = 1;
static int s_rect_mode = RECT_CORNER;
// Ancrage de circle/ellipse. Ces primitives sont centrées depuis toujours : le
// défaut reste donc "center", à l'inverse de rect.
static const int ELLIPSE_CORNER = 0;
static const int ELLIPSE_CENTER = 1;
static int s_ellipse_mode = ELLIPSE_CENTER;

// En mode coin, l'appelant a passé le coin supérieur gauche de la boîte
// englobante : le ramener au centre, seule forme comprise par les tracés.
static void anchor_oval(float* cx, float* cy, float rx, float ry) {
    if (s_ellipse_mode == ELLIPSE_CORNER) {
        *cx += rx;
        *cy += ry;
    }
}
static bool s_has_stroke = true;
static Color s_stroke_color = WHITE;
static bool s_has_fill = false;
static Color s_fill_color = WHITE;
static int s_segments = 64;

static void apply_stroke_size(float sz) {
    s_stroke_size = sz;
}

static void apply_font_size(float sz) {
    s_font_size = sz;
}

// Police du tracé de texte, telle que le script l'a choisie.
static Font current_font() {
    return engine_font(s_font_idx);
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
int gfx_logical_width() {
    return s_logicalW;
}

int gfx_logical_height() {
    return s_logicalH;
}

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
    float font_size;
    int font_idx;
    int rect_mode;
    int ellipse_mode;
    int sprite_mode;
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
    s.font_size = s_font_size;
    s.font_idx = s_font_idx;
    s.rect_mode = s_rect_mode;
    s.ellipse_mode = s_ellipse_mode;
    s.sprite_mode = image_get_sprite_mode();
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
    s_font_size = s.font_size;
    s_font_idx = s.font_idx;
    s_rect_mode = s.rect_mode;
    s_ellipse_mode = s.ellipse_mode;
    image_set_sprite_mode(s.sprite_mode);
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
    apply_font_size(18.0f);   // taille la plus courante → pas besoin de l'écrire
    s_font_idx = engine_font_default();
    s_rect_mode = RECT_CORNER;
    s_ellipse_mode = ELLIPSE_CENTER;
    image_set_sprite_mode(SPRITE_CORNER);
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

// graphics.fontSize([hauteur]) : fixe la hauteur de la police, et renvoie TOUJOURS la
// hauteur courante — sans argument, c'est donc un simple accesseur.
static int gfx_font_size(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc > 0 && args[0].is_number())
        apply_font_size((float)args[0].as_num());
    return ctx.ret(Value((double)s_font_size));
}

// graphics.font([nom]) : choisit la police courante parmi celles du moteur, et renvoie
// TOUJOURS son nom. Un nom inconnu est une erreur nommant les polices disponibles :
// mieux vaut le signaler que dessiner silencieusement avec une autre police.
static int gfx_font(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc > 0 && !args[0].is_nil()) {
        if (!args[0].is_string())
            throw std::runtime_error("graphics.font: expected a font name");
        std::string name = args[0].as_string();
        int idx = engine_font_index(name.c_str());
        if (idx < 0) {
            std::string known;
            for (int i = 0; i < engine_font_count(); ++i) {
                if (i > 0)
                    known += ", ";
                known += engine_font_name(i);
            }
            throw std::runtime_error("graphics.font: unknown font '" + name + "' (available: " + known + ")");
        }
        s_font_idx = idx;
    }
    return ctx.ret(Value(std::string(engine_font_name(s_font_idx))));
}

// graphics.textSize(texte) : largeur et hauteur du texte AVEC la police et la taille
// courantes — deux valeurs, pour centrer ou aligner sans réimplémenter la mesure.
static int gfx_text_size(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("graphics.textSize: expected a text");
    std::string text = args[0].as_string();
    Font font = current_font();
    if (font.texture.id == 0 || font.baseSize == 0) {
        // Sans zone graphique aucune police n'est chargée : renvoyer 0 plutôt que de
        // diviser par la hauteur native (comme graphics.text, qui ne dessine rien).
        ctx.set_result(0, Value(0.0));
        ctx.set_result(1, Value(0.0));
        return 2;
    }
    Vector2 size = MeasureTextEx(font, text.c_str(), s_font_size, s_font_size / (float)font.baseSize);
    ctx.set_result(0, Value((double)size.x));
    ctx.set_result(1, Value((double)size.y));
    return 2;
}

// Argument d'un mode d'ancrage : "corner" (0) ou "center" (1) — valeurs partagées
// par les constantes RECT_*, ELLIPSE_* et SPRITE_*. Sans argument, on revient au
// défaut de la primitive, qui n'est pas le même pour rect et pour ellipse.
static int anchor_mode_arg(CallCtx& ctx, const char* fn, int dflt) {
    if (ctx.argc == 0)
        return dflt;
    if (!ctx.args[0].is_string())
        throw std::runtime_error(std::string(fn) + ": attendu \"corner\" ou \"center\"");
    const std::string& s = ctx.args[0].as_string();
    if (s == "corner")
        return 0;
    if (s == "center")
        return 1;
    throw std::runtime_error(std::string(fn) + ": mode inconnu '" + s + "'");
}

static int gfx_rect_mode(CallCtx& ctx) {
    s_rect_mode = anchor_mode_arg(ctx, "graphics.rectMode", RECT_CORNER) == 0 ? RECT_CORNER : RECT_CENTER;
    return ctx.ret(Value{});
}

static int gfx_ellipse_mode(CallCtx& ctx) {
    s_ellipse_mode = anchor_mode_arg(ctx, "graphics.ellipseMode", ELLIPSE_CENTER) == 0 ? ELLIPSE_CORNER : ELLIPSE_CENTER;
    return ctx.ret(Value{});
}

static int gfx_sprite_mode(CallCtx& ctx) {
    image_set_sprite_mode(anchor_mode_arg(ctx, "graphics.spriteMode", SPRITE_CORNER) == 0 ? SPRITE_CORNER
                                                                                        : SPRITE_CENTER);
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
        throw std::runtime_error("graphics.rect: expected x, y, w, h[, r]");
    double wn = gfx_to_num(args[2]);
    double hn = gfx_to_num(args[3]);
    double xn = gfx_to_num(args[0]);
    double yn = gfx_to_num(args[1]);
    // Mode centre : x,y désignent le CENTRE. Le décalage est appliqué avant la
    // conversion en entier, sinon une taille impaire biaiserait la position.
    if (s_rect_mode == RECT_CENTER) {
        xn -= wn * 0.5;
        yn -= hn * 0.5;
    }
    int x = (int)xn;
    int y = (int)yn;
    int w = (int)wn;
    int h = (int)hn;
    Rectangle rec = {(float)x, (float)y, (float)w, (float)h};
    // Rayon de coin optionnel, en PIXELS — c'est de la géométrie, donc un argument.
    // raylib attend une FRACTION de 0 à 1 dont il tire radius = min(w,h)*roundness/2 :
    // on convertit, et on borne à la moitié du petit côté (au-delà, c'est une gélule).
    double r = (argc > 4 && args[4].is_number()) ? args[4].as_num() : 0.0;
    int side = (w < h) ? w : h;
    if (r > 0.0 && side > 0) {
        float roundness = (float)(2.0 * r / side);
        if (roundness > 1.0f)
            roundness = 1.0f;
        if (s_has_fill)
            DrawRectangleRounded(rec, roundness, s_segments, s_fill_color);
        if (s_has_stroke) {
            StrokeWC s = stroke_params();
            // Conventions OPPOSÉES dans raylib : DrawRectangleLinesEx trace la bande à
            // l'INTÉRIEUR du rectangle, DrawRectangleRoundedLinesEx à l'EXTÉRIEUR — son
            // cas roundness<=0 le montre, il élargit de lineThick avant de déléguer.
            // On rétrécit donc de l'épaisseur pour que le contour reste DANS la géométrie
            // déclarée, comme sur le chemin à angles droits. Le rayon suit : la bande
            // intérieure porte r - épaisseur, si bien qu'un rayon entièrement mangé par
            // le trait redonne exactement le rectangle carré.
            float t = s.w;
            float iw = (float)w - 2.0f * t;
            float ih = (float)h - 2.0f * t;
            if (iw > 0.0f && ih > 0.0f) {
                float iside = (iw < ih) ? iw : ih;
                float ir = (float)r - t;
                float iround = (ir > 0.0f) ? 2.0f * ir / iside : 0.0f;
                if (iround > 1.0f)
                    iround = 1.0f;
                DrawRectangleRoundedLinesEx({(float)x + t, (float)y + t, iw, ih}, iround, s_segments, t, s.c);
            } else {
                // Trait plus épais que la moitié du petit côté : la bande couvre toute
                // la forme. Le chemin à angles droits la remplit alors (mesuré : un
                // carré 20x20 au trait 12 allume ses 400 pixels) → même dégradation ici,
                // plutôt que de ne rien dessiner.
                DrawRectangleRounded(rec, roundness, s_segments, s.c);
            }
        }
        return ctx.ret(Value{});
    }
    if (s_has_fill)
        DrawRectangle(x, y, w, h, s_fill_color);
    if (s_has_stroke) {
        StrokeWC s = stroke_params();
        DrawRectangleLinesEx(rec, s.w, s.c);
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

// Capture demandée par l'HÔTE (bouton du mode plein écran, cf. wasm_main) et non par
// le script : le PNG est produit en MÉMOIRE, encodé en base64, puis retiré par
// gfx_take_capture. Comme graphics.screenshot, elle est DIFFÉRÉE en fin de frame — c'est
// le seul moment où le framebuffer par défaut contient l'écran composé (sans
// preserveDrawingBuffer, le navigateur l'efface après composition).
static bool s_capture_pending = false;
static std::string s_capture_b64;

void gfx_request_capture() {
    s_capture_pending = true;
    s_capture_b64.clear();
}

// Oublie toute demande et toute image non retirée : un nouveau programme ne doit pas
// honorer la capture demandée pour le précédent (attente expirée puis « Relancer »).
static void gfx_reset_capture() {
    s_capture_pending = false;
    s_capture_b64.clear();
}

std::string gfx_take_capture() {
    std::string out = s_capture_b64;   // retirée : une capture n'est livrée qu'une fois
    s_capture_b64.clear();
    return out;
}

static void flush_pending_capture() {
    if (!s_capture_pending)
        return;
    s_capture_pending = false;
    Image img = LoadImageFromScreen();   // batch déjà vidé par l'appelant (cf. ci-dessous)
    int size = 0;
    unsigned char* png = ExportImageToMemory(img, ".png", &size);
    if (png != nullptr && size > 0)
        s_capture_b64 = image_b64_encode(png, (size_t)size);
    if (png != nullptr)
        MemFree(png);
    UnloadImage(img);
}

// Exécute une capture en attente : appelé en fin de frame par renderFrame, quand
// le framebuffer par défaut contient l'image composée (écran réellement affiché).
static void flush_pending_screenshot() {
    if (!s_shot_pending && !s_capture_pending)
        return;
    // Le batch rlgl doit être EXÉCUTÉ avant toute lecture de pixels : la composition de la
    // render texture n'est encore qu'un quad en attente, et lire l'écran ici rendait une
    // image entièrement noire (constaté au navigateur).
    rlDrawRenderBatchActive();
    flush_pending_capture();
    if (!s_shot_pending)
        return;
    s_shot_pending = false;
    TakeScreenshot(s_shot_path.c_str());
}

static int gfx_text(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 3)
        throw std::runtime_error("graphics.text: expected text, x, y");
    const char* text = args[0].is_string() ? args[0].as_string().c_str() : "";
    // Style pris dans l'ÉTAT courant, comme toutes les autres primitives : couleur
    // de trait (écrire, c'est tracer au stylo) et taille de police via fontSize().
    // Seule la géométrie passe en argument.
    //
    // DrawTextEx et non DrawText : ce dernier prend un int, donc tronquerait la
    // taille (biais systématique vers le bas sur une taille mise à l'échelle), et
    // relève toute valeur < 10 à 10. Ici la taille flottante est transmise telle
    // quelle, sans plancher.
    // L'espacement de DrawText vaut fontSize/baseSize en division ENTIÈRE, donc il
    // avance par paliers (1 de 10 à 19, 2 de 20 à 29…) ; on garde la même intention
    // en continu, soit le facteur d'échelle lui-même.
    Font font = current_font();
    // Garde que DrawText appliquait et que l'appel direct à DrawTextEx perdait :
    // sans canvas, la police par défaut n'est pas chargée (glyphs nul, baseSize à 0)
    // → division par zéro puis déréférencement nul. Ne rien dessiner, comme avant.
    if (font.texture.id == 0 || font.baseSize == 0)
        return ctx.ret(Value{});
    float spacing = s_font_size / (float)font.baseSize;
    Vector2 pos = {(float)gfx_to_int(args[1]), (float)gfx_to_int(args[2])};
    DrawTextEx(font, text, pos, s_font_size, spacing, s_stroke_color);
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
    anchor_oval(&cx, &cy, rx, ry);
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
    anchor_oval(&cx, &cy, rx, ry);
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

// Overlay mémoire/FPS dessiné par le moteur après chaque frame, dans le coin BAS
// droit — le haut est laissé à l'interface `ui`. Couleur vive + ombre portée : lisible
// quel que soit le fond de la scène.
static const int OVERLAY_SIZE = 16;
static const int OVERLAY_MARGIN = 8;

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
    const int size = OVERLAY_SIZE, margin = OVERLAY_MARGIN;
    int tw = MeasureText(buf, size);
    int x = s_logicalW - tw - margin;
    int y = s_logicalH - size - margin;
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
    // Les widgets voient le clic AVANT le script : s'ils le consomment, mouse.pressed
    // n'est pas appelé — cliquer un bouton ne déclenche donc pas aussi l'action de la
    // scène. C'est la raison d'être d'un module natif plutôt qu'une classe Ollin.
    mouse_poll(ui_poll());
    // Tweens avancés AVANT la logique et le dessin : update() comme draw() voient donc
    // les valeurs de la frame courante. Même dt que la globale deltaTime.
    tween_update_all(s_frame_dt);
    call_update_if_any();
    VM::current()->call_value(const_cast<Value&>(draw_fn));
    end3d_internal();   // no-op hors 3D ; sinon flush + refermer si draw() a oublié end3d
    ui_draw();          // par-dessus la scène, dans la même render texture
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
    m.map_set(Value(std::string("fontSize")), Value::make_builtin(gfx_font_size));
    m.map_set(Value(std::string("font")), Value::make_builtin(gfx_font));
    m.map_set(Value(std::string("textSize")), Value::make_builtin(gfx_text_size));
    m.map_set(Value(std::string("rectMode")), Value::make_builtin(gfx_rect_mode));
    m.map_set(Value(std::string("ellipseMode")), Value::make_builtin(gfx_ellipse_mode));
    m.map_set(Value(std::string("spriteMode")), Value::make_builtin(gfx_sprite_mode));
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
