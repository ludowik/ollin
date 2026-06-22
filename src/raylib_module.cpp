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
    if (v.isMap() || v.isClass()) {
        // Color components are stored as [0.0, 1.0] — convert to [0, 255] for Raylib
        auto getComp = [&](const char* k, double def) -> uint8_t {
            Value f = v.mapGet(Value(std::string(k)));
            return f.isNumber() ? (uint8_t)(f.asNum() * 255.0 + 0.5) : (uint8_t)(def * 255.0 + 0.5);
        };
        return { getComp("r", 0), getComp("g", 0), getComp("b", 0), getComp("a", 1) };
    }
    if (!v.isInteger()) return WHITE;
    int64_t c = v.asInt();
    return { (uint8_t)(c >> 24 & 0xFF), (uint8_t)(c >> 16 & 0xFF),
             (uint8_t)(c >>  8 & 0xFF), (uint8_t)(c & 0xFF) };
}

static int64_t rgb(uint8_t r, uint8_t g, uint8_t b) {
    return ((int64_t)r << 24) | ((int64_t)g << 16) | ((int64_t)b << 8) | 255;
}

static Value gfx_canvas(Value* args, int argc) {
    int w = argc > 0 ? toInt(args[0]) : 800;
    int h = argc > 1 ? toInt(args[1]) : 600;
    const char* title = (argc > 2 && args[2].isString()) ? args[2].sptr->c_str() : "Ollin";
#ifdef __EMSCRIPTEN__
    if (IsWindowReady()) CloseWindow();
    EM_ASM({
        var c = document.getElementById('canvas');
        if (c) { c.width = $0; c.height = $1; c.style.display = 'block'; }
        var o = document.getElementById('pg-output');
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

static Value gfx_line(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("graphics.line: expected x1, y1, x2, y2 [, thickness [, color]]");
    float thick = argc > 4 ? (args[4].isNumber() ? (float)args[4].asNum() : 1.0f) : 1.0f;
    Color color = argc > 5 ? toColor(args[5]) : WHITE;
    if (thick <= 1.0f) {
        DrawLine(toInt(args[0]), toInt(args[1]), toInt(args[2]), toInt(args[3]), color);
    } else {
        DrawLineEx({(float)args[0].asNum(), (float)args[1].asNum()},
                   {(float)args[2].asNum(), (float)args[3].asNum()},
                   thick, color);
    }
    return Value{};
}

static Value gfx_fps(Value* args, int argc) {
    (void)args; (void)argc;
    return Value((int64_t)GetFPS());
}

static Value gfx_draw_text(Value* args, int argc) {
    if (argc < 4) throw std::runtime_error("graphics.draw_text: expected text, x, y, size [, color]");
    const char* text = (args[0].isString()) ? args[0].sptr->c_str() : "";
    DrawText(text, toInt(args[1]), toInt(args[2]), toInt(args[3]),
             argc > 4 ? toColor(args[4]) : WHITE);
    return Value{};
}

static Value gfx_close(Value* args, int argc) {
    (void)args; (void)argc;
    CloseWindow();
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
        VM::current()->callValue(fn);
        EndDrawing();
    }
    CloseWindow();
#endif
    return Value{};
}

Value makeGraphicsModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("canvas")),  Value::makeBuiltin(gfx_canvas));
    m.mapSet(Value(std::string("is_open")), Value::makeBuiltin(gfx_is_open));
    m.mapSet(Value(std::string("begin_draw")), Value::makeBuiltin(gfx_begin_draw));
    m.mapSet(Value(std::string("end_draw")),   Value::makeBuiltin(gfx_end_draw));
    m.mapSet(Value(std::string("clear")),   Value::makeBuiltin(gfx_clear));
    m.mapSet(Value(std::string("line")),     Value::makeBuiltin(gfx_line));
    m.mapSet(Value(std::string("fps")),       Value::makeBuiltin(gfx_fps));
    m.mapSet(Value(std::string("draw_text")), Value::makeBuiltin(gfx_draw_text));
    m.mapSet(Value(std::string("close")),    Value::makeBuiltin(gfx_close));
    m.mapSet(Value(std::string("quit")),     Value::makeBuiltin(gfx_quit));
    m.mapSet(Value(std::string("run")),      Value::makeBuiltin(gfx_run));
    m.mapSet(Value(std::string("BLACK")),   Value(rgb(0,   0,   0)));
    m.mapSet(Value(std::string("WHITE")),   Value(rgb(255, 255, 255)));
    m.mapSet(Value(std::string("RED")),     Value(rgb(230, 41,  55)));
    m.mapSet(Value(std::string("GREEN")),   Value(rgb(0,   228, 48)));
    m.mapSet(Value(std::string("BLUE")),    Value(rgb(0,   121, 241)));
    m.mapSet(Value(std::string("YELLOW")),  Value(rgb(253, 249, 0)));
    m.mapSet(Value(std::string("GRAY")),    Value(rgb(130, 130, 130)));
    return m;
}
