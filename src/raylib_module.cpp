#include "chunk.h"
#include "vm.h"
#include <raylib.h>
#include <stdexcept>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

static int toInt(const Value& v) {
    if (v.isInteger()) return (int)v.asInt();
    if (v.isFloat())   return (int)v.asFloat();
    return 0;
}

static Color toColor(const Value& v) {
    if (!v.isMap() && !v.isClass())
        throw std::runtime_error("expected a Color object");
    auto getComp = [&](const char* k, double def) -> uint8_t {
        Value f = v.mapGet(Value(std::string(k)));
        return f.isNumber() ? (uint8_t)(f.asNum() * 255.0 + 0.5) : (uint8_t)(def * 255.0 + 0.5);
    };
    return { getComp("r", 0), getComp("g", 0), getComp("b", 0), getComp("a", 1) };
}

static Value colorInst(double r, double g, double b) {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("r")), Value(r));
    m.mapSet(Value(std::string("g")), Value(g));
    m.mapSet(Value(std::string("b")), Value(b));
    m.mapSet(Value(std::string("a")), Value(1.0));
    return m;
}

static Value gfx_canvas(Value* args, int argc) {
    int w = argc > 0 ? toInt(args[0]) : 800;
    int h = argc > 1 ? toInt(args[1]) : 600;
    const char* title = (argc > 2 && args[2].isString()) ? args[2].asString().c_str() : "Ollin";
#ifdef __EMSCRIPTEN__
    if (IsWindowReady()) CloseWindow();
    EM_ASM({
        var c = document.getElementById('canvas');
        if (c) { c.width = $0; c.height = $1; c.style.display = 'block'; }
        var o = document.getElementById('output');
        if (o) o.style.display = 'none';
    }, w, h);
#endif
    InitWindow(w, h, title);
#ifdef __EMSCRIPTEN__
    SetTargetFPS(0);
#else
    SetTargetFPS(60);
#endif
    return Value{};
}

static Value gfx_is_open(Value* args, int argc) {
    (void)args; (void)argc;
    return Value(WindowShouldClose() ? int64_t(0) : int64_t(1));
}

static Value gfx_begin_draw(Value* args, int argc) {
    (void)args; (void)argc;
    BeginDrawing();
    return Value{};
}

static Value gfx_end_draw(Value* args, int argc) {
    (void)args; (void)argc;
    EndDrawing();
    return Value{};
}

static Value gfx_clear(Value* args, int argc) {
    ClearBackground(argc > 0 ? toColor(args[0]) : BLACK);
    return Value{};
}

// ── Style state ───────────────────────────────────────────────────────────────
static float s_stroke_size  = 2.0f;
static bool  s_has_stroke   = true;
static Color s_stroke_color = WHITE;
static bool  s_has_fill     = false;
static Color s_fill_color   = WHITE;

static void applyStrokeSize(float sz)            { s_stroke_size = sz; }
static void applyStroke(bool en, Color c = WHITE) { s_has_stroke = en; s_stroke_color = c; }
static void applyFill(bool en, Color c = WHITE)   { s_has_fill = en; s_fill_color = c; }

static void resetStyles() {
    applyStrokeSize(2.0f);
    applyStroke(true, WHITE);
    applyFill(false);
}

static Value gfx_stroke_size(Value* args, int argc) {
    if (argc > 0 && args[0].isNumber())
        applyStrokeSize((float)args[0].asNum());
    return Value{};
}

static Value gfx_stroke(Value* args, int argc) {
    if (argc > 0 && (args[0].isMap() || args[0].isClass()))
        applyStroke(true, toColor(args[0]));
    else
        applyStroke(false);
    if (argc > 1 && args[1].isNumber())
        applyStrokeSize((float)args[1].asNum());
    return Value{};
}

static Value gfx_fill(Value* args, int argc) {
    if (argc > 0 && (args[0].isMap() || args[0].isClass()))
        applyFill(true, toColor(args[0]));
    else
        applyFill(false);
    return Value{};
}

static Value gfx_line(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("graphics.line: expected x1, y1, x2, y2");
    if (!s_has_stroke) return Value{};
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
    if (argc < 4) throw std::runtime_error("graphics.rect: expected x, y, w, h");
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
    (void)args; (void)argc;
    return Value((int64_t)GetFPS());
}

static Value gfx_draw_text(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("graphics.draw_text: expected text, x, y, size [, color]");
    const char* text = args[0].isString() ? args[0].asString().c_str() : "";
    DrawText(text, toInt(args[1]), toInt(args[2]), toInt(args[3]),
             argc > 4 ? toColor(args[4]) : s_stroke_color);
    return Value{};
}

static Value gfx_close(Value* args, int argc) {
    (void)args; (void)argc;
    CloseWindow();
    return Value{};
}

static Value gfx_ellipse(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("graphics.ellipse: expected x, y, width, height");
    int   cx = (int)args[0].asNum();
    int   cy = (int)args[1].asNum();
    float rx = (float)args[2].asNum() * 0.5f;
    float ry = (float)args[3].asNum() * 0.5f;
    float half = s_stroke_size * 0.5f;
    if (s_has_fill && s_has_stroke) {
        DrawEllipse(cx, cy, rx + half, ry + half, s_stroke_color);
        DrawEllipse(cx, cy, std::max(0.0f, rx - half), std::max(0.0f, ry - half), s_fill_color);
    } else if (s_has_fill) {
        DrawEllipse(cx, cy, rx, ry, s_fill_color);
    } else if (s_has_stroke) {
        DrawEllipseLines(cx, cy, rx, ry, s_stroke_color);
    }
    return Value{};
}

static Value gfx_circle(Value* args, int argc) {
    if (argc < 3) throw std::runtime_error("graphics.circle: expected x, y, radius");
    float x = (float)args[0].asNum();
    float y = (float)args[1].asNum();
    float r = (float)args[2].asNum();
    if (s_has_fill)
        DrawCircleV({x, y}, r, s_fill_color);
    if (s_has_stroke) {
        float half = s_stroke_size * 0.5f;
        DrawRing({x, y}, r - half, r + half, 0.0f, 360.0f, 36, s_stroke_color);
    }
    return Value{};
}

static Value gfx_point(Value* args, int argc) {
    if (argc < 2) throw std::runtime_error("graphics.point: expected x, y");
    if (!s_has_stroke) return Value{};
    float x = (float)args[0].asNum();
    float y = (float)args[1].asNum();
    DrawCircleV({x, y}, s_stroke_size, s_stroke_color);
    return Value{};
}

static bool s_quit = false;

static Value gfx_quit(Value* args, int argc) {
    (void)args; (void)argc;
#ifdef __EMSCRIPTEN__
    emscripten_cancel_main_loop();
#else
    s_quit = true;
#endif
    return Value{};
}

#ifdef __EMSCRIPTEN__
static Value  s_run_callback;
static void emscripten_frame() {
    BeginDrawing();
    resetStyles();
    VM::current()->callValue(s_run_callback);
    EndDrawing();
}
#endif

static Value gfx_run(Value* args, int argc) {
    if (argc < 1) throw std::runtime_error("graphics.run: expected callback function");
    Value fn = args[0];
#ifdef __EMSCRIPTEN__
    s_run_callback = fn;
    emscripten_set_main_loop(emscripten_frame, 0, 0);
#else
    s_quit = false;
    while (!WindowShouldClose() && !s_quit) {
        BeginDrawing();
        resetStyles();
        VM::current()->callValue(fn);
        EndDrawing();
    }
    CloseWindow();
#endif
    return Value{};
}

Value makeGraphicsModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("canvas")),     Value::makeBuiltin(gfx_canvas));
    m.mapSet(Value(std::string("is_open")),    Value::makeBuiltin(gfx_is_open));
    m.mapSet(Value(std::string("begin_draw")), Value::makeBuiltin(gfx_begin_draw));
    m.mapSet(Value(std::string("end_draw")),   Value::makeBuiltin(gfx_end_draw));
    m.mapSet(Value(std::string("clear")),       Value::makeBuiltin(gfx_clear));
    m.mapSet(Value(std::string("strokeSize")), Value::makeBuiltin(gfx_stroke_size));
    m.mapSet(Value(std::string("stroke")),     Value::makeBuiltin(gfx_stroke));
    m.mapSet(Value(std::string("fill")),       Value::makeBuiltin(gfx_fill));
    m.mapSet(Value(std::string("line")),       Value::makeBuiltin(gfx_line));
    m.mapSet(Value(std::string("rect")),       Value::makeBuiltin(gfx_rect));
    m.mapSet(Value(std::string("fps")),        Value::makeBuiltin(gfx_fps));
    m.mapSet(Value(std::string("draw_text")),  Value::makeBuiltin(gfx_draw_text));
    m.mapSet(Value(std::string("close")),      Value::makeBuiltin(gfx_close));
    m.mapSet(Value(std::string("quit")),       Value::makeBuiltin(gfx_quit));
    m.mapSet(Value(std::string("run")),        Value::makeBuiltin(gfx_run));
    m.mapSet(Value(std::string("ellipse")),    Value::makeBuiltin(gfx_ellipse));
    m.mapSet(Value(std::string("circle")),     Value::makeBuiltin(gfx_circle));
    m.mapSet(Value(std::string("point")),      Value::makeBuiltin(gfx_point));
    m.mapSet(Value(std::string("BLACK")),   colorInst(0.0,        0.0,        0.0));
    m.mapSet(Value(std::string("WHITE")),   colorInst(1.0,        1.0,        1.0));
    m.mapSet(Value(std::string("RED")),     colorInst(230/255.0,  41/255.0,   55/255.0));
    m.mapSet(Value(std::string("GREEN")),   colorInst(  0/255.0, 228/255.0,   48/255.0));
    m.mapSet(Value(std::string("BLUE")),    colorInst(  0/255.0, 121/255.0,  241/255.0));
    m.mapSet(Value(std::string("YELLOW")),  colorInst(253/255.0, 249/255.0,    0/255.0));
    m.mapSet(Value(std::string("GRAY")),    colorInst(130/255.0, 130/255.0,  130/255.0));
    return m;
}
