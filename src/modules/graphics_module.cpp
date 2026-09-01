#include "graphics_internal.h"
#include "audio_module.h"
#include "sound_module.h"
#include "touch_module.h"
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

// gfx_to_int is provided inline by graphics_internal.h, shared between 2D and 3D.
// gfx_to_color is declared in graphics_internal.h and defined here; graphics3d.cpp reads it too.
Color gfx_to_color(const Value& v) {
    if (!v.is_map() && !v.is_class())
        throw std::runtime_error("expected a Color object");
    auto get_comp = [&](const char* k, double def) -> uint8_t {
        Value f = v.map_get(Value(std::string(k)));
        return f.is_number() ? (uint8_t)(f.as_num() * 255.0 + 0.5) : (uint8_t)(def * 255.0 + 0.5);
    };
    return {get_comp("r", 0), get_comp("g", 0), get_comp("b", 0), get_comp("a", 1)};
}

// A [0,1] component to a clamped [0,255] byte.
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
static int s_logicalW = 0; // the area's logical width, used by the memory and FPS overlay
static int s_logicalH = 0; // the area's logical height
// PERSISTENT drawing context: draw() renders into this RenderTexture, which is NOT cleared between
// frames — it is up to draw() to call graphics.clear() when it wants a fresh background. It is
// blitted to the screen every frame with the FPS overlay ON TOP, so the overlay stays crisp and does
// not smear.
static RenderTexture2D s_target{};
static bool s_target_ready = false;
static int s_targetW = 0, s_targetH = 0;   // the render texture's real size, supersampled
// Target supersampling RELATIVE to the logical size, for anti-aliasing, bounded below by the physical
// resolution and above by a ceiling (see gfx_canvas) — and NOT multiplied by the DPR.
static const int SSAA = 2;
// Current blend mode, set by graphics.blendMode and tracked so it can be restored after a fade — a
// clear with alpha — and reset to ALPHA every frame.
static int s_blend_mode = BLEND_ALPHA;
// Screenshot DEFERRED to the end of the frame: draw() renders into the RT, while the capture must read
// the composed screen. Cleared on every gfx_canvas, so a request from a previous program does not leak
// through the shared WASM instance.
static std::string s_shot_path;
static bool s_shot_pending = false;
static void flush_pending_screenshot();   // defined below; used by gfx_end_draw
static void gfx_reset_capture();          // likewise; used by gfx_canvas
// reset_3d_lighting_state, reset_3d_graphics_state and end_3d_internal are declared in graphics_internal.h and defined in graphics3d.cpp.
// ONE graphics.run per program. The engine (run_entry_hooks) calls graphics.run(draw) automatically
// when a draw() exists; if the script ALSO calls it explicitly we would get two loops, hence a double
// CloseWindow (a native crash) or a double emscripten_set_main_loop on WASM. This guard ignores the
// second call, and is reset to false in gfx_canvas — the start of a program — so a playground re-run
// works.
static bool s_run_active = false;

static int gfx_canvas(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    int w = argc > 0 ? gfx_to_int(args[0]) : 800;
    int h = argc > 1 ? gfx_to_int(args[1]) : 600;
    // The title is written by the author, so a string is MANDATORY: a number there is a mistake,
    // and it used to become "Ollin" in silence. A value is inserted the ordinary way, through an
    // interpolation — graphics.canvas(W, H, "level {n}").
    if (argc > 2 && !args[2].is_string())
        throw std::runtime_error("graphics.canvas: the title must be a string");
    std::string title = argc > 2 ? args[2].as_string() : std::string("Ollin");
    s_shot_pending = false;   // a new program: forget any pending screenshot
    gfx_reset_capture();      // likewise for the capture the host asked for
    s_blend_mode = BLEND_ALPHA;
    // The 3D lighting is reset HERE, before setup() or the top level set ambient and light — and not
    // in gfx_run, which runs AFTER and would wipe the configuration.
    reset3d_lighting_state();
    s_run_active = false;   // a new program, hence ONE graphics.run allowed again
#ifdef __EMSCRIPTEN__
    // REUSE the WebGL context between two playground runs instead of CloseWindow followed by
    // InitWindow. Every InitWindow (re)creates a WebGL context on the same canvas and recompiles
    // raylib's default shader; with enough churn iOS LOSES the contexts and loading that shader fails
    // from the very next run on ("detachShader must be an instance of WebGLProgram", even in 2D — it
    // is the default shader, not ours). So we keep ONE context for the whole session and merely
    // resize it.
    bool reuse = IsWindowReady();
    if (reuse) {
        if (s_target_ready) {                 // free the old target: the context is reused, so the ids are valid
            UnloadRenderTexture(s_target);
            s_target_ready = false;
        }
        reset3d_graphics_state();               // free the 3D shader, meshes, textures and VBOs in THIS context
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
        SetWindowSize(w, h);                   // the same WebGL context, a new logical size
        SetWindowTitle(title.c_str());
    } else {
        SetConfigFlags(FLAG_MSAA_4X_HINT);
        InitWindow(w, h, title.c_str());
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
        reset3d_graphics_state();   // free the 3D GL resources before any reinitialisation
    }
    s_physW = w;
    s_physH = h;
    SetConfigFlags(FLAG_MSAA_4X_HINT);
    InitWindow(w, h, title.c_str());
    SetTargetFPS(60);
#endif
    s_logicalW = w;
    s_logicalH = h;
    // Repositions the engine globals on the canvas's real size: W and H to the logical dimensions, CX
    // and CY to the centre as floats. graphics.canvas(w, h) therefore recomputes them even when w and h
    // differ from the initial window values.
    if (VM* vm = VM::current()) {
        vm->set_global("W", Value((int64_t)w));
        vm->set_global("H", Value((int64_t)h));
        vm->set_global("CX", Value((double)w / 2.0));
        vm->set_global("CY", Value((double)h / 2.0));
    }
    // Persistent render target. We aim for supersampling RELATIVE to the logical size for
    // anti-aliasing, but never below the physical resolution, to stay sharp on HiDPI. SSAA is
    // therefore NOT multiplied by the DPR: on mobile, with a DPR of 2 or more, the texture used to
    // blow up — memory, and GL_MAX_TEXTURE_SIZE exceeded, giving a black screen. The size is capped as
    // well.
    const int MAX_RT = 4096;   // a safe bound, at most GL_MAX_TEXTURE_SIZE on most GPUs
    s_targetW = s_physW > s_logicalW * SSAA ? s_physW : s_logicalW * SSAA;
    s_targetH = s_physH > s_logicalH * SSAA ? s_physH : s_logicalH * SSAA;
    if (s_targetW > MAX_RT) {
        s_targetW = MAX_RT;
    }
    if (s_targetH > MAX_RT) {
        s_targetH = MAX_RT;
    }
    s_target = LoadRenderTexture(s_targetW, s_targetH);
    // Check the allocation: when the FBO or the texture could not be created — too large, not enough
    // VRAM — we stay in DIRECT rendering (render_frame falls back) rather than sample an invalid
    // texture and show a black screen.
    s_target_ready = (s_target.id != 0 && s_target.texture.id != 0);
    if (s_target_ready) {
        SetTextureFilter(s_target.texture, TEXTURE_FILTER_BILINEAR);   // smoothing when scaled down
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
        vm->mark_gfx_canvas();   // an explicit canvas, so no implicit one (run_entry_hooks)
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
    flush_pending_screenshot();   // the manual beginDraw/endDraw path: the capture happens here
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
        // A semi-transparent colour means a FADE, as in p5.js background(r,g,b,a<255), and NOT a clean
        // erase: we paint a translucent full-screen rectangle in ALPHA blending, which fades the
        // persistent content towards `c`. Ideal for trails. ALPHA is forced for the duration of the
        // rectangle, then the current blend mode — the one graphics.blendMode set in draw() — is
        // restored.
        BeginBlendMode(BLEND_ALPHA);
        rlPushMatrix();                 // the fade is independent of the current transform
        rlLoadIdentity();               // (like ClearBackground) covers the whole canvas
        DrawRectangle(0, 0, s_logicalW, s_logicalH, c);
        rlPopMatrix();
        BeginBlendMode(s_blend_mode);
    } else {
        ClearBackground(c);   // opaque → effacement net (glClear)
    }
    return ctx.ret(Value{});
}

// Blend mode for the drawing that follows. Accepts a string ("alpha", "add", "multiply", "subtract",
// "add_colors", "premultiply") or a constant from the `blend` module. Reset to "alpha" at the start of
// every frame, in reset_styles.
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
            throw std::runtime_error("graphics.blendMode: unknown mode '" + s + "'");
        }
    } else if (argc > 0 && args[0].is_number()) {
        mode = (int)args[0].as_num();   // a constant of the `blend` module
    } else if (argc > 0) {
        // A mode is an IDENTIFIER, so a wrong type is refused: it used to fall back to ALPHA in
        // silence, and the drawing then simply ignored the mode asked for.
        throw std::runtime_error("graphics.blendMode: expected a mode name or a blend constant");
    }
    s_blend_mode = mode;
    BeginBlendMode(mode);
    return ctx.ret(Value{});
}

static float s_stroke_size = 2.0f;
static float s_font_size = 18.0f;   // the font size, a piece of state like s_stroke_size
// Current font, an index into the engine registry (engine_font.h). It is a style STATE like the size,
// so push and pushStyle save it and every frame resets it to the default.
static int s_font_idx = engine_font_default();
// Anchoring for rect: x,y is the top-left corner by default, or the centre. It is a STATE like
// blendMode — it does not change the geometry but how it is read.
static const int RECT_CORNER = 0;
static const int RECT_CENTER = 1;
static int s_rect_mode = RECT_CORNER;
// Anchoring for text, on the two axes separately: x is the left edge, the middle or the right edge,
// y is the top of the line, its bottom, or the BASELINE — the line the letters sit on, which is
// what one aligns text to when mixing sizes. "corner" is accepted as a synonym of "left", so the
// word used by rect and sprite keeps its meaning here.
static const int TEXT_LEFT = 0;
static const int TEXT_CENTER = 1;
static const int TEXT_RIGHT = 2;
static int s_text_mode = TEXT_LEFT;
static const int TEXT_TOP = 0;
static const int TEXT_BOTTOM = 1;
static const int TEXT_BASELINE = 2;
static int s_text_valign = TEXT_TOP;
// Anchoring for circle and ellipse. Those primitives have always been centred, so the default stays
// "center", unlike rect.
static const int ELLIPSE_CORNER = 0;
static const int ELLIPSE_CENTER = 1;
static int s_ellipse_mode = ELLIPSE_CENTER;

// In corner mode the caller passed the top-left corner of the bounding box, so we bring it back to the
// centre, the only form the drawing routines understand.
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

// Font used for text drawing, as chosen by the script.
static Font current_font() {
    return engine_font(s_font_idx);
}

// Sub-pixel strokes: the RenderTexture has no MSAA, so a thickness below 1 renders as dots — partial
// coverage without smoothing. We approximate anti-aliasing by keeping a CONTINUOUS 1 px stroke and
// modulating the alpha by the coverage, that is by the thickness, giving a thin continuous line that
// pales as the size drops.
static void subpixel_stroke(float& w, Color& c) {
    if (w < 1.0f) {
        float cov = w < 0.0f ? 0.0f : w;
        c.a = (unsigned char)(c.a * cov + 0.5f);
        w = 1.0f;
    }
}

// Current stroke thickness and colour, adjusted for sub-pixel rendering.
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

// Style-state accessors, declared in graphics_internal.h and read by graphics3d.cpp.
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

// Style contexts, kept on a stack.
// Saves and restores the WHOLE drawing state: stroke, fill, blend mode, image tint (image_module) and
// the current 3D texture (graphics3d). Used by push/pop, which cover the matrix and the style, and by
// pushStyle/popStyle, which cover the style alone.
struct StyleState {
    float stroke_size;
    float font_size;
    int font_idx;
    int rect_mode;
    int ellipse_mode;
    int sprite_mode;
    int   text_mode;
    int   text_valign;
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
    s.text_mode = s_text_mode;
    s.text_valign = s_text_valign;
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
    s_text_mode = s.text_mode;
    s_text_valign = s.text_valign;
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
    apply_font_size(18.0f);   // the most common size, so it need not be written out
    s_font_idx = engine_font_default();
    s_rect_mode = RECT_CORNER;
    s_ellipse_mode = ELLIPSE_CENTER;
    image_set_sprite_mode(SPRITE_CORNER);
    s_text_mode = TEXT_LEFT;
    s_text_valign = TEXT_TOP;
    apply_stroke(true, WHITE);
    apply_fill(false);
    image_set_tint(false, 255, 255, 255, 255);   // no tint by default; like fill and stroke, it is reset every frame
    s_blend_mode = BLEND_ALPHA;                   // the blend mode returns to its default every frame
    reset3d_frame_state();                          // the 3D texture returns to "none", hence white, every frame
    s_style_stack.clear();                        // the style stack starts afresh every frame; push and pop are balanced within draw
    BeginBlendMode(BLEND_ALPHA);
    rlLoadIdentity();
}

static int gfx_stroke_size(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc > 0 && args[0].is_number())
        apply_stroke_size((float)args[0].as_num());
    return ctx.ret(Value{});
}

// graphics.fontSize([height]) sets the font height and ALWAYS returns the current one, so with no
// argument it is simply an accessor.
static int gfx_font_size(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc > 0 && args[0].is_number())
        apply_font_size((float)args[0].as_num());
    return ctx.ret(Value((double)s_font_size));
}

// graphics.font([name]) picks the current font among the engine's and ALWAYS returns its name. An
// unknown name is an error that lists the available fonts: better to report it than to silently draw
// with a different one.
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

// What the text PRIMITIVES draw is converted, never refused: `graphics.text(score, x, y)` writes
// the number, and an instance goes through its `__str`, exactly as `print` would. Only these two
// convert — everywhere else a string argument is mandatory, since a title or a diagnostic message
// is written by the author and a number there is a mistake, not a shortcut.
//
// ⚠ The conversion may run Ollin code (an instance's `__str`), which can resize the register file:
// read every OTHER argument before calling this, or `args` will dangle.
static std::string drawn_text(const Value* args, int argc, int i) {
    if (i >= argc)
        return std::string();
    return value_to_string(args[i]);
}


// graphics.textSize(text) gives the width and height of the text WITH the current font and size — two
// values, so centring or aligning needs no reimplementation of the measurement.
static int gfx_text_size(CallCtx& ctx) {
    Value* args = ctx.args;
    int argc = ctx.argc;
    if (argc < 1)
        throw std::runtime_error("graphics.textSize: expected a text");
    Font font = current_font();
    if (font.texture.id == 0 || font.baseSize == 0) {
        // With no drawing area no font is loaded, so we return 0 rather than divide by the native
        // height — the same choice as graphics.text, which draws nothing.
        ctx.set_result(0, Value(0.0));
        ctx.set_result(1, Value(0.0));
        return 2;
    }
    // Same conversion as graphics.text, and for the same reason: measuring must agree with
    // drawing, or a number could be written but never centred.
    std::string text = drawn_text(args, argc, 0);
    Vector2 size = MeasureTextEx(font, text.c_str(), s_font_size, s_font_size / (float)font.baseSize);
    ctx.set_result(0, Value((double)size.x));
    ctx.set_result(1, Value((double)size.y));
    return 2;
}

// A MODE argument: a name from a list, answered as its position in that list. The list also writes
// the error messages, so the words accepted are spelled once — they were written by hand in each
// caller, and the renaming of a single mode meant editing the comparison and two messages
// separately. `i` is the argument's position, so a primitive anchored on two axes reads one list
// per axis. With no argument the caller's default is returned: a mode call describes the mode in
// full rather than half-remembering the last one.
static int mode_arg(CallCtx& ctx, int i, const char* fn, const char* const* names, int count, int dflt) {
    std::string expected;
    for (int k = 0; k < count; k++)
        expected += (k == 0 ? "\"" : (k + 1 == count ? " or \"" : ", \"")) + std::string(names[k]) + "\"";
    if (i >= ctx.argc)
        return dflt;
    if (!ctx.args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": expected " + expected);
    const std::string& given = ctx.args[i].as_string();
    for (int k = 0; k < count; k++) {
        if (given == names[k])
            return k;
    }
    throw std::runtime_error(std::string(fn) + ": unknown mode '" + given + "' (expected " + expected + ")");
}

// The CORNER value is 0 in each of these families, and CENTER is 1, so a mode reads straight out of
// its position in the list.
static const char* const CORNER_CENTER[] = {"corner", "center"};

static int gfx_rect_mode(CallCtx& ctx) {
    s_rect_mode = mode_arg(ctx, 0, "graphics.rectMode", CORNER_CENTER, 2, RECT_CORNER);
    return ctx.ret(Value{});
}

static int gfx_ellipse_mode(CallCtx& ctx) {
    s_ellipse_mode = mode_arg(ctx, 0, "graphics.ellipseMode", CORNER_CENTER, 2, ELLIPSE_CENTER);
    return ctx.ret(Value{});
}

static int gfx_sprite_mode(CallCtx& ctx) {
    image_set_sprite_mode(mode_arg(ctx, 0, "graphics.spriteMode", CORNER_CENTER, 2, SPRITE_CORNER));
    return ctx.ret(Value{});
}

// Two lists rather than one, because "corner" and "left" are the SAME anchor: the word rect and
// sprite use keeps its meaning here. The default is therefore the first name, as for every other
// family.
static const char* const TEXT_H_NAMES[] = {"left", "corner", "center", "right"};
static const int TEXT_H_VALUES[] = {TEXT_LEFT, TEXT_LEFT, TEXT_CENTER, TEXT_RIGHT};
static const char* const TEXT_V_NAMES[] = {"top", "bottom", "baseline"};

static int gfx_text_mode(CallCtx& ctx) {
    // Both axes are read BEFORE either is written: writing as the arguments were parsed left an
    // invalid call having already wiped the mode in force, so a script catching the error found
    // itself back at left/top without asking. A refused call must change nothing.
    int horizontal = TEXT_H_VALUES[mode_arg(ctx, 0, "graphics.textMode", TEXT_H_NAMES, 4, 0)];
    int vertical = mode_arg(ctx, 1, "graphics.textMode", TEXT_V_NAMES, 3, TEXT_TOP);
    s_text_mode = horizontal;
    s_text_valign = vertical;
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
        s_has_stroke = true;                   // with no argument it (re)enables with the current colour
        return ctx.ret(Value{});
    }
    ColorRGBA k = parse_color(args, argc, "stroke");
    apply_stroke(true, rgba_color(k.r, k.g, k.b, k.a));
    // The optional size is accepted only with a Color object as first argument — stroke(Color, size).
    // For the numeric forms use graphics.strokeSize, since there the numbers are the colour.
    if ((args[0].is_map() || args[0].is_class()) && argc > 1 && args[1].is_number())
        apply_stroke_size((float)args[1].as_num());
    return ctx.ret(Value{});
}

static int gfx_no_stroke(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    s_has_stroke = false;                       // stop drawing an outline, the colour being kept
    return ctx.ret(Value{});
}

static int gfx_fill(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0) {
        s_has_fill = true;                   // with no argument it (re)enables with the current colour
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
    s_has_fill = false;                       // stop filling, the colour being kept
    return ctx.ret(Value{});
}

// Global image tint for graphics.sprite and image.draw: a Color object, or r,g,b[,a].
static int gfx_tint(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 0)
        return ctx.ret(Value{});   // with no argument: changes nothing
    ColorRGBA k = parse_color(args, argc, "tint");   // the same signature as clear, fill and stroke
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
    StrokeWC s = stroke_params();   // a thin continuous line: below 1 the alpha is modulated, instead of dashes
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
    // Centre mode: x,y denote the CENTRE. The offset is applied before the conversion to integers,
    // otherwise an odd size would bias the position.
    if (s_rect_mode == RECT_CENTER) {
        xn -= wn * 0.5;
        yn -= hn * 0.5;
    }
    int x = (int)xn;
    int y = (int)yn;
    int w = (int)wn;
    int h = (int)hn;
    Rectangle rec = {(float)x, (float)y, (float)w, (float)h};
    // Optional corner radius, in PIXELS — it is geometry, hence an argument. raylib expects a FRACTION
    // from 0 to 1, from which it derives radius = min(w,h)*roundness/2, so we convert and clamp to half
    // the shorter side; beyond that it is a capsule.
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
            // raylib uses OPPOSITE conventions: DrawRectangleLinesEx draws the band INSIDE the
            // rectangle, DrawRectangleRoundedLinesEx OUTSIDE it — its roundness<=0 case shows this, as
            // it widens by lineThick before delegating. We therefore shrink by the thickness so the
            // outline stays WITHIN the declared geometry, as on the square-cornered path. The radius
            // follows: the inner band carries r minus the thickness, so a radius entirely eaten by the
            // stroke gives back exactly the square rectangle.
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
                // A stroke thicker than half the shorter side covers the whole shape. The
                // square-cornered path then fills it — measured: a 20x20 square with a 12 stroke lights
                // all 400 pixels — so we degrade the same way here rather than draw nothing.
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

// Captures the DISPLAYED framebuffer into a PNG. Since draw() renders into the persistent
// RenderTexture, which is bound during draw, the composed screen cannot be captured here: the capture
// is DEFERRED to the end of the frame, after composition, in render_frame — or in gfx_end_draw on the
// manual path. On WASM, TakeScreenshot triggers a download. See s_shot_path and s_shot_pending
// above.
static int gfx_screenshot(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("graphics.screenshot: expected a file path");
    s_shot_path = args[0].as_string();
    s_shot_pending = true;
    return ctx.ret(Value{});
}

// A capture requested by the HOST — the fullscreen button, see wasm_main — rather than by the script:
// the PNG is produced IN MEMORY, encoded as base64, then collected by gfx_take_capture. Like
// graphics.screenshot it is DEFERRED to the end of the frame, the only moment when the default
// framebuffer holds the composed screen: without preserveDrawingBuffer the browser clears it after
// compositing.
static bool s_capture_pending = false;
static std::string s_capture_b64;

void gfx_request_capture() {
    s_capture_pending = true;
    s_capture_b64.clear();
}

// Forgets any request and any image not collected: a new program must not honour a capture asked for
// the previous one, after a timeout followed by "Run again".
static void gfx_reset_capture() {
    s_capture_pending = false;
    s_capture_b64.clear();
}

std::string gfx_take_capture() {
    std::string out = s_capture_b64;   // taken away: a capture is delivered once only
    s_capture_b64.clear();
    return out;
}

static void flush_pending_capture() {
    if (!s_capture_pending)
        return;
    s_capture_pending = false;
    Image img = LoadImageFromScreen();   // the batch was already flushed by the caller, see below
    int size = 0;
    unsigned char* png = ExportImageToMemory(img, ".png", &size);
    if (png != nullptr && size > 0)
        s_capture_b64 = image_b64_encode(png, (size_t)size);
    if (png != nullptr)
        MemFree(png);
    UnloadImage(img);
}

// Performs a pending capture. Called at the end of the frame by render_frame, when the default
// framebuffer holds the composed image — what is actually on screen.
static void flush_pending_screenshot() {
    if (!s_shot_pending && !s_capture_pending)
        return;
    // The rlgl batch must be FLUSHED before any pixel read: the render texture's composition is still
    // only a pending quad, and reading the screen here gave an entirely black image (observed in the
    // browser).
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
    // ANY value is drawn, converted exactly as `print` converts it — an instance's `__str`
    // included. A non-string used to become the empty string, so `graphics.text(score, x, y)`
    // drew nothing at all, in silence: neither a result nor a diagnosis.
    //
    // The geometry is read BEFORE the conversion, because `__str` is Ollin code: calling it can
    // resize the register file, and `args` would then dangle.
    int tx = gfx_to_int(args[1]);
    int ty = gfx_to_int(args[2]);
    // The style comes from the current STATE, like every other primitive: the stroke colour — writing
    // is drawing with a pen — and the font size through fontSize(). Only the geometry is passed as an
    // argument.
    //
    // DrawTextEx rather than DrawText: the latter takes an int, so it would truncate the size (a
    // systematic downward bias on a scaled size) and raises anything below 10 to 10. Here the floating
    // size is passed through untouched, with no floor.
    // DrawText's spacing is fontSize/baseSize in INTEGER division, so it advances in steps — 1 from 10
    // to 19, 2 from 20 to 29 — and we keep the same intent continuously, which is the scale factor
    // itself.
    Font font = current_font();
    // A guard DrawText applied and that calling DrawTextEx directly lost: with no canvas the default
    // font is not loaded (null glyphs, baseSize at 0), which means a division by zero and then a null
    // dereference. Draw nothing, as before.
    if (font.texture.id == 0 || font.baseSize == 0)
        return ctx.ret(Value{});
    // Converted only once the canvas is known to exist: with no drawing area nothing is drawn, so
    // an `__str` must not run either.
    std::string text = drawn_text(args, argc, 0);
    float spacing = s_font_size / (float)font.baseSize;
    Vector2 pos = {(float)tx, (float)ty};
    // Only the anchors that need the text MEASURED pay for it: measuring walks the whole string,
    // and a baseline needs the font's ascent alone. Guarding both axes at once made "left" plus
    // "baseline" — what the Primitives sample uses — measure for nothing.
    if (s_text_mode != TEXT_LEFT || s_text_valign == TEXT_BOTTOM) {
        Vector2 size = MeasureTextEx(font, text.c_str(), s_font_size, spacing);
        if (s_text_mode == TEXT_CENTER)
            pos.x -= size.x / 2.0f;
        else if (s_text_mode == TEXT_RIGHT)
            pos.x -= size.x;
        if (s_text_valign == TEXT_BOTTOM)
            pos.y -= size.y;
    }
    if (s_text_valign == TEXT_BASELINE)
        pos.y -= engine_font_ascent(font, s_font_size);
    DrawTextEx(font, text.c_str(), pos, s_font_size, spacing, s_stroke_color);
    return ctx.ret(Value{});
}

static int gfx_close(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    CloseWindow();
    return ctx.ret(Value{});
}

static void poly_fill(std::vector<Vector2> pts, Color color) {
    int n = (int)pts.size();
    if (n < 3)
        return;
    // Normalize to counter-clockwise. With screen coordinates (Y down) a positive shoelace means
    // clockwise, so the order is reversed.
    float area = 0;
    for (int i = 0; i < n; i++) {
        const auto& a = pts[i];
        const auto& b = pts[(i + 1) % n];
        area += (b.x - a.x) * (b.y + a.y);
    }
    if (area > 0)
        std::reverse(pts.begin(), pts.end());
    // A fan from the centroid.
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
            throw std::runtime_error(std::string(fn) + ": point coordinates must be numbers");
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

// Draws a thick polyline with ROUND JOINS and CAPS. At high thickness, independent DrawLineEx calls
// leave notches at the vertices — unjoined corners, a cogwheel look. A disc of radius thickness/2 at
// each vertex fills the outer gap and gives a round join, and round caps at the ends of an open
// polyline. Below about 2 px it is imperceptible and skipped, for performance and with no visible
// effect.
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

// A thick ellipse outline is a triangulated ring between an INNER contour (r - thickness/2) and an
// OUTER one (r + thickness/2), the thickness being centred on the path, as in p5.js. We used to draw
// `segs` thick segments with DrawLineEx: at high thickness their unjoined corners stuck out and gave a
// cogwheel look. The ring stays smooth.
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
        // The quad (o0,o1,i1,i0) becomes two triangles, wound like draw_ellipse_fill.
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
            // A circle uses raylib's native ring: a smooth outline, thickness centred on r.
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

// A sector, or pie slice: triangles from the centre over the arc [start;stop].
static void draw_arc_fill(float cx, float cy, float rx, float ry, float start, float stop, Color color, int segs) {
    for (int i = 0; i < segs; i++) {
        float a0 = start + (stop - start) * (float)i / segs;
        float a1 = start + (stop - start) * (float)(i + 1) / segs;
        DrawTriangle({cx, cy}, {cx + rx * cosf(a1), cy + ry * sinf(a1)}, {cx + rx * cosf(a0), cy + ry * sinf(a0)},
                     color);
    }
}

// The arc's outline ALONE — the curve, without the radii: a ring triangulated over [start;stop] with
// the thickness centred on the path, built exactly like draw_ellipse_stroke.
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
        // Winding matches draw_arc_fill (front-facing), otherwise it would be culled and invisible.
        DrawTriangle(o0, i1, o1, color);
        DrawTriangle(o0, i0, i1, color);
    }
}

// arc(x, y, w, h, start, stop) draws an elliptical arc. w and h are full sizes, as for ellipse, and
// start and stop are in radians, clockwise — with y pointing down, an increasing angle turns clockwise.
// A fill gives a solid sector, a stroke the arc's curve alone, and segs is proportional to the
// angle.
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
static bool s_quit = false; // the native loop only (WASM: emscripten_cancel_main_loop)
#endif

// The frame delta is measured BY US: a wall clock (GetTime()) read at a SINGLE point per frame, on
// entry to render_frame. raylib's GetFrameTime() and GetFPS() are NOT used: in our web loop — one
// requestAnimationFrame per frame, drawing into a persistent RenderTexture — their notion of a frame,
// update plus draw, leaves out the rAF wait BETWEEN two frames, so dt comes out too small. The
// consequences were a deltaTime too small, hence a simulation in slow motion, and an overestimated FPS
// (76 displayed for a real 60). The wall gap between two frame entries, by contrast, is exact.
//
// A frame the loop did not RUN is not time the program spent, and that interruption is DECLARED,
// never guessed. Whoever stops the loop — the playground's pause button, a hidden tab, a window
// losing focus — arms gfx_clock_break(), and the first frame back counts ZERO instead of the wall
// gap. Capping the gap instead was tried and rejected: it still credited the bound itself (0.25 s
// of animation appearing out of nowhere on every resume) and it punished a frame that was merely
// slow. Measured before any of this: a 5 s pause produced a deltaTime of 5.126 s, with elapsedTime
// jumping from 4.88 to 12.25, sending every tween straight to its end.
static double s_frame_dt = 0.0;          // the last frame's duration, in seconds
static bool s_clock_break = false;       // the next gap covers an interruption: it counts zero
static double s_last_frame_time = -1.0;  // the previous frame's timestamp
static double s_fps_ema = 0.0;           // the smoothed FPS, an exponential average

// Declares that the loop stopped: the next frame's gap covers the interruption, not running time.
// Called by the host (the playground's pause and its capture, which resumes the loop for one frame)
// and by the engine itself when the window comes back.
void gfx_clock_break() {
    s_clock_break = true;
}

#ifndef __EMSCRIPTEN__
// Desktop: losing focus or being minimised may stop the loop, depending on the platform and the
// window manager. The transition is what matters — coming BACK is where a gap would otherwise be
// credited — so one frame is written off at that point. When the loop kept running throughout, that
// costs one frame's worth of time, which no animation can show.
static bool s_window_active = true;

static void check_window_activity() {
    bool active = IsWindowFocused() && !IsWindowMinimized();
    if (active && !s_window_active)
        gfx_clock_break();
    s_window_active = active;
}
#else
// The web signals it properly: the browser stops calling requestAnimationFrame for a hidden tab and
// fires visibilitychange, blur and focus. The listeners are installed ONCE and only raise a flag,
// which the frame reads — a call back into C would mean an export to keep in step with this file.
static void install_clock_watch() {
    static bool installed = false;
    if (installed)
        return;
    installed = true;
    EM_ASM({
        if (window.__ollinClockWatch)
            return;
        window.__ollinClockWatch = 1;
        window.__ollinClockBreak = 0;
        var mark = function() { window.__ollinClockBreak = 1; };
        document.addEventListener('visibilitychange', mark);
        window.addEventListener('focus', mark);
        window.addEventListener('blur', mark);
        window.addEventListener('pageshow', mark);
    });
}

static void check_window_activity() {
    install_clock_watch();
    if (EM_ASM_INT({
            var b = window.__ollinClockBreak;
            window.__ollinClockBreak = 0;
            return b ? 1 : 0;
        }))
        gfx_clock_break();
}
#endif

// Memory and FPS overlay drawn by the engine after each frame, in the BOTTOM right corner — the top is
// left to the `ui` interface. A bright colour plus a drop shadow keeps it readable whatever the scene's
// background.
static const int OVERLAY_SIZE = 16;
static const int OVERLAY_MARGIN = 8;

static void draw_fps_overlay() {
    // FPS computed from OUR delta, which is reliable, and smoothed to avoid flicker.
    if (s_frame_dt > 0.0) {
        double inst = 1.0 / s_frame_dt;
        s_fps_ema = (s_fps_ema <= 0.0) ? inst : (s_fps_ema * 0.9 + inst * 0.1);
    }
    int fps = (int)(s_fps_ema + 0.5);
    // Memory used, next to the FPS: KB below 1 MB, MB above.
    double kb = ollin_heap_bytes() / 1024.0;
    const char* buf = (kb >= 1024.0) ? TextFormat("%.1f Mo  %d fps", kb / 1024.0, fps)
                                     : TextFormat("%.0f Ko  %d fps", kb, fps);
    const int size = OVERLAY_SIZE, margin = OVERLAY_MARGIN;
    int tw = MeasureText(buf, size);
    int x = s_logicalW - tw - margin;
    int y = s_logicalH - size - margin;
    DrawText(buf, x + 1, y + 1, size, BLACK);     // a drop shadow, for contrast
    DrawText(buf, x, y, size, {0, 228, 48, 255}); // bright green (lime)
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

// Time accumulated since the program started, reset to 0 on every gfx_run.
static double s_elapsed_time = 0.0;

// Updates deltaTime and elapsedTime in the VM and calls update(dt) when it is defined.
static Value s_update_callback;
static void call_update_if_any() {
    double dt = s_frame_dt;   // our own reliable measure, not GetFrameTime() (see above)
    s_elapsed_time += dt;
    VM* vm = VM::current();
    vm->set_global("deltaTime", Value(dt));
    vm->set_global("elapsedTime", Value(s_elapsed_time));
    if (s_update_callback.is_callable())
        vm->call_value(s_update_callback, Value(dt));
}

// Renders ONE frame. The context is NOT cleared by default: draw() paints into the persistent target
// s_target — it is up to draw() to call graphics.clear() for a fresh background — then s_target is
// blitted to the screen and the FPS overlay is laid ON TOP, so it stays crisp and never accumulates.
// `tex` and `drawing` report which blocks are open, for a safe cleanup should draw() throw inside the
// web loop.
// The shared prelude of a frame: default styles, input, logic (update), then the user's rendering
// (draw). Shared by both paths of render_frame.
static void run_user_callbacks(const Value& draw_fn) {
    reset_styles();
    keyboard_poll();
    // The widgets see the click BEFORE the script: when they consume it, mouse.pressed is not called,
    // so clicking a button does not also trigger the scene's action. That is the reason for a native
    // module rather than an Ollin class.
    // Contacts first: a `mouse` callback may read touch.count(), since mouse emulation on a single
    // finger delivers the gesture twice and it is up to the script to decide.
    touch_begin_frame();
    mouse_poll(ui_poll());
    // Multitouch comes AFTER the mouse and does not replace it: on a single finger the system emulates
    // the mouse, so both families of callbacks fire. A script picks the one it listens to — a deliberate
    // decision: nothing is filtered.
    touch_poll();
    // Sound opens on the first gesture: the browser refuses to sound before an interaction, so the
    // script has nothing to write for its beeps to come out. The keyboard goes through its own module,
    // because keyboard_poll has already CONSUMED raylib's queue and GetKeyPressed would return nothing
    // here.
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT) || GetTouchPointCount() > 0 || keyboard_pressed_any())
        audio_wake();
    audio_update();
    sound_update();
    // The tweens are advanced BEFORE the logic and the drawing, so update() and draw() both see this
    // frame's values. Same dt as the deltaTime global.
    tween_update_all(s_frame_dt);
    call_update_if_any();
    VM::current()->call_value(const_cast<Value&>(draw_fn));
    end3d_internal();   // a no-op outside 3D; otherwise it flushes and closes, should draw() have forgotten end3d
    ui_draw();          // over the scene, in the same render texture
}

static void render_frame(const Value& draw_fn, bool* tex, bool* drawing) {
    *tex = false;
    *drawing = false;
    // Frame delta: the wall gap since the previous frame's entry, which includes the rAF wait, unlike
    // GetFrameTime. On the first frame dt is 0.
    double now = GetTime();
    check_window_activity();
    bool interrupted = s_clock_break || s_last_frame_time < 0.0;
    s_clock_break = false;
    s_frame_dt = interrupted ? 0.0 : (now - s_last_frame_time);
    s_last_frame_time = now;
    if (s_target_ready) {
        BeginTextureMode(s_target);   // binds the FBO; does NOT clear
        *tex = true;
        // The RT is at physical resolution, but BeginTextureMode installed a projection in physical
        // pixels. We replace it with the LOGICAL extents, origin at the top left as raylib does, so
        // draw() keeps logical coordinates over [0,w]×[0,h] while rendering at full physical
        // resolution. This goes on the PROJECTION and not the modelview, so it survives
        // graphics.resetTransform.
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
        // OPAQUE composition (src=ONE, dst=ZERO): the RT's RGB is copied as is, ignoring ITS alpha
        // channel — otherwise an RT with low alpha, after a clear(...,a) fade or translucent drawing,
        // would look ghostly. It is also essential not to inherit the blend mode draw() left behind
        // (ADD, say), which would distort both the composition and the overlay.
        rlSetBlendFactors(RL_ONE, RL_ZERO, RL_FUNC_ADD);
        BeginBlendMode(BLEND_CUSTOM);
        // s_target is in SSAA-times-physical pixels and stored bottom-up, so the source is the RT's real
        // size with a negative height to display it upright, and the destination is in logical
        // coordinates, filling the screen through the physical viewport. The SSAA-to-physical reduction
        // by the bilinear filter is what smooths the image.
        DrawTexturePro(s_target.texture,
                       Rectangle{0.0f, 0.0f, (float)s_targetW, -(float)s_targetH},
                       Rectangle{0.0f, 0.0f, (float)s_logicalW, (float)s_logicalH},
                       Vector2{0.0f, 0.0f}, 0.0f, WHITE);
        flush_pending_screenshot();      // captures the composed screen, before the FPS overlay
        BeginBlendMode(BLEND_ALPHA);   // the FPS overlay, in normal blending
        draw_fps_overlay();
        *drawing = false;
        EndDrawing();
    } else {
        // Fallback: no persistent canvas configured, so render directly, as the engine used to.
        BeginDrawing();
        *drawing = true;
        if (s_physW != GetScreenWidth() || s_physH != GetScreenHeight())
            rlViewport(0, 0, s_physW, s_physH);
        run_user_callbacks(draw_fn);
        flush_pending_screenshot();      // captures the screen, before the FPS overlay
        draw_fps_overlay();
        *drawing = false;
        EndDrawing();
    }
}

#ifdef __EMSCRIPTEN__
static Value s_run_callback;
static void emscripten_frame() {
    // A runtime error in update() or draw() surfaces here, outside ollin_run's try/catch, since the loop
    // is asynchronous. Uncaught, the exception would crash the WASM silently and freeze the screen. We
    // catch it, stop the loop, and hand the message to the playground to display in place of the
    // canvas.
    bool tex = false, drawing = false;
    try {
        render_frame(s_run_callback, &tex, &drawing);
    } catch (const std::exception& e) {
        if (tex)                   // close the blocks left open, without ending twice
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
    if (s_run_active)   // already started for this program, so the second call is ignored (see s_run_active)
        return ctx.ret(Value{});
    s_run_active = true;
    Value fn = args[0];
    s_elapsed_time = 0.0;
    s_last_frame_time = -1.0;   // first frame: dt = 0, so there is no initial jump
    s_fps_ema = 0.0;
    keyboard_reset();            // a fresh keyboard state: the static s_down survives between WASM runs
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

// Matrix transformations and style contexts.
// push and pop save and restore BOTH the matrix AND the style, as in Processing and p5.
// pushMatrix and popMatrix cover the matrix alone; pushStyle and popStyle the style alone.
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

// graphics.translate(x, y [, z]): z is optional and defaults to 0, so this serves 2D and 3D alike.
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

// A rotation of deg degrees (argument 0) about the axis (ax,ay,az) — the common factor of rotate,
// whose default axis is Z, and of rotateX, rotateY and rotateZ.
static void rotate_axis(Value* args, int argc, float ax, float ay, float az, const char* fn) {
    rlRotatef((float)num_arg(args, argc, 0, fn), ax, ay, az);
}

// graphics.rotate(deg [, ax, ay, az]): with no axis it turns about Z, with all three components it is
// a 3D rotation about (ax,ay,az). A PARTIAL axis, two or three arguments, is an ERROR — we do not
// silently fall back to Z.
static int gfx_rotate(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc == 1) {
        rotate_axis(args, argc, 0.0f, 0.0f, 1.0f, "graphics.rotate");   // the Z axis by default
    } else if (argc >= 4) {
        rlRotatef((float)num_arg(args, argc, 0, "graphics.rotate"), (float)num_arg(args, argc, 1, "graphics.rotate"),
                  (float)num_arg(args, argc, 2, "graphics.rotate"), (float)num_arg(args, argc, 3, "graphics.rotate"));
    } else {
        throw std::runtime_error("graphics.rotate: expected deg [, ax, ay, az] (a whole axis, or none)");
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

// graphics.scale(s | sx,sy | sx,sy,sz): one argument is uniform (s,s,s), two give (sx,sy,1) for 2D, and
// three give (sx,sy,sz).
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
        sy = sx;   // uniform on all three axes
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


// The `blend` module exposes the blend modes through raylib's enums DIRECTLY, keeping a single source
// of truth with no literals to maintain or check. It is defined here rather than in modules.cpp,
// because that file also compiles without raylib.
Value make_blend_module() {
    return MapBuilder()
        .int_num("ALPHA", BLEND_ALPHA)
        .int_num("ADD", BLEND_ADDITIVE)
        .int_num("MULTIPLY", BLEND_MULTIPLIED)
        .int_num("ADD_COLORS", BLEND_ADD_COLORS)
        .int_num("SUBTRACT", BLEND_SUBTRACT_COLORS)
        .int_num("PREMULTIPLY", BLEND_ALPHA_PREMULTIPLY)
        .done();
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
    m.map_set(Value(std::string("textMode")), Value::make_builtin(gfx_text_mode));
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
    register3d_graphics(m);   // 3D: the camera, begin3d/end3d, the primitives, the lighting and the texture — graphics3d.cpp
    // The colour constants are NOT here: use the `colors` module.
    return m;
}
