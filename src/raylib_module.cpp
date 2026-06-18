#include "chunk.h"
#include <raylib.h>
#include <stdexcept>

static int toInt(const Value& v) {
    if (v.isInteger()) return (int)v.asInt();
    if (v.isFloat())   return (int)v.asFloat();
    return 0;
}

static Color toColor(const Value& v) {
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
    InitWindow(w, h, title);
    SetTargetFPS(60);
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
    if (argc < 4) throw std::runtime_error("graphics.line: expected x1, y1, x2, y2 [, color]");
    DrawLine(toInt(args[0]), toInt(args[1]), toInt(args[2]), toInt(args[3]),
             argc > 4 ? toColor(args[4]) : WHITE);
    return Value{};
}

static Value gfx_fps(Value* args, int argc) {
    (void)args; (void)argc;
    return Value((int64_t)GetFPS());
}

static Value gfx_draw_fps(Value* args, int argc) {
    int x = argc > 0 ? toInt(args[0]) : 0;
    int y = argc > 1 ? toInt(args[1]) : 0;
    DrawFPS(x, y);
    return Value{};
}

static Value gfx_close(Value* args, int argc) {
    (void)args; (void)argc;
    CloseWindow();
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
    m.mapSet(Value(std::string("fps")),      Value::makeBuiltin(gfx_fps));
    m.mapSet(Value(std::string("draw_fps")), Value::makeBuiltin(gfx_draw_fps));
    m.mapSet(Value(std::string("close")),    Value::makeBuiltin(gfx_close));
    m.mapSet(Value(std::string("BLACK")),   Value(rgb(0,   0,   0)));
    m.mapSet(Value(std::string("WHITE")),   Value(rgb(255, 255, 255)));
    m.mapSet(Value(std::string("RED")),     Value(rgb(230, 41,  55)));
    m.mapSet(Value(std::string("GREEN")),   Value(rgb(0,   228, 48)));
    m.mapSet(Value(std::string("BLUE")),    Value(rgb(0,   121, 241)));
    m.mapSet(Value(std::string("YELLOW")),  Value(rgb(253, 249, 0)));
    m.mapSet(Value(std::string("GRAY")),    Value(rgb(130, 130, 130)));
    return m;
}
