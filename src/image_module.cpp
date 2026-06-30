#include "image_module.h"
#include "modules/module_utils.h"
#include <cstdint>
#include <raylib.h>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

// ── storage ───────────────────────────────────────────────────────────────────

struct TexHandle {
    bool is_render = false;
    bool pixels_open = false;
    Texture2D tex = {};
    RenderTexture2D rtt = {};
    Image cpu = {};
};

static std::unordered_map<int, TexHandle> s_images;
static int s_next_id = 1;

// preloaded bytes: name → (bytes, ext with dot e.g. ".png")
static std::unordered_map<std::string, std::pair<std::vector<uint8_t>, std::string>> s_preloaded;

// ── base64 decode ─────────────────────────────────────────────────────────────

static std::vector<uint8_t> b64decode(const std::string& s) {
    static const int8_t T[256] = {
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 0-15
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 16-31
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63, // 32-47 (+/)
        52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1, // 48-63 (0-9)
        -1, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, // 64-79 (A-O)
        15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1, // 80-95 (P-Z)
        -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, // 96-111 (a-o)
        41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1, // 112-127 (p-z)
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 128-143
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 144-159
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 160-175
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 176-191
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 192-207
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 208-223
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 224-239
        -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // 240-255
    };
    std::vector<uint8_t> out;
    out.reserve(s.size() * 3 / 4);
    int bits = 0, val = 0;
    for (unsigned char c : s) {
        int8_t d = T[c];
        if (d < 0)
            continue;
        val = (val << 6) | d;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back((uint8_t)((val >> bits) & 0xFF));
            val &= (1 << bits) - 1;
        }
    }
    return out;
}

// ── WASM interop ──────────────────────────────────────────────────────────────

void image_preload(const std::string& name, const std::vector<uint8_t>& bytes, const std::string& ext) {
    s_preloaded[name] = {bytes, ext};
}

void image_preload_b64(const std::string& name, const std::string& b64, const std::string& ext) {
    std::string dotExt = (!ext.empty() && ext[0] == '.') ? ext : ("." + ext);
    image_preload(name, b64decode(b64), dotExt);
}

void image_reset() {
    for (auto& [id, h] : s_images) {
        if (!IsWindowReady())
            break;
        if (h.pixels_open) {
            UnloadImage(h.cpu);
        }
        if (h.is_render)
            UnloadRenderTexture(h.rtt);
        else
            UnloadTexture(h.tex);
    }
    s_images.clear();
    s_next_id = 1;
}

// ── helpers ───────────────────────────────────────────────────────────────────

static Value makeHandle(int id, int w, int h) {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("id")), Value((int64_t)id));
    m.mapSet(Value(std::string("width")), Value((int64_t)w));
    m.mapSet(Value(std::string("height")), Value((int64_t)h));
    return m;
}

static int handleId(const Value& v, const char* fn) {
    if (!v.isMap())
        throw std::runtime_error(std::string(fn) + ": expected image handle");
    Value id = v.mapGet(Value(std::string("id")));
    if (!id.isInteger())
        throw std::runtime_error(std::string(fn) + ": invalid handle");
    return (int)id.asInt();
}

static TexHandle& findHandle(int id, const char* fn) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        throw std::runtime_error(std::string(fn) + ": unknown image id " + std::to_string(id));
    return it->second;
}

static Color toColor(const Value& v) {
    if (!v.isMap())
        throw std::runtime_error("image: expected Color object");
    auto gc = [&](const char* k, double def) -> uint8_t {
        Value f = v.mapGet(Value(std::string(k)));
        return f.isNumber() ? (uint8_t)(f.asNum() * 255.0 + 0.5) : (uint8_t)(def * 255.0);
    };
    return {gc("r", 1), gc("g", 1), gc("b", 1), gc("a", 1)};
}

static void pixelsOpen(TexHandle& h) {
    if (h.pixels_open)
        return;
    if (!h.is_render)
        throw std::runtime_error("image: pixel access requires a render texture (use image.create())");
    h.cpu = LoadImageFromTexture(h.rtt.texture);
    // WebGL/WASM: glReadPixels via temp FBO may fail on a fresh render texture
    // that has never been drawn to — fall back to a zeroed CPU image.
    if (!h.cpu.data)
        h.cpu = GenImageColor(h.rtt.texture.width, h.rtt.texture.height, BLANK);
    h.pixels_open = true;
}

static void pixelsClose(TexHandle& h) {
    if (!h.pixels_open)
        return;
    UpdateTexture(h.rtt.texture, h.cpu.data);
    UnloadImage(h.cpu);
    h.cpu = {};
    h.pixels_open = false;
}

static Texture2D loadFromMemory(const std::vector<uint8_t>& bytes, const std::string& ext) {
    Image img = LoadImageFromMemory(ext.c_str(), bytes.data(), (int)bytes.size());
    if (!img.data)
        throw std::runtime_error("image: failed to decode image (ext: " + ext + ")");
    Texture2D tex = LoadTextureFromImage(img);
    UnloadImage(img);
    return tex;
}

// ── image.load(path) ──────────────────────────────────────────────────────────

static Value img_load(Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("image.load: expected path string");
    const std::string& path = args[0].asString();

    TexHandle h;
    auto it = s_preloaded.find(path);
    if (it != s_preloaded.end()) {
        h.tex = loadFromMemory(it->second.first, it->second.second);
    } else {
        h.tex = LoadTexture(path.c_str());
        if (h.tex.id == 0)
            throw std::runtime_error("image.load: cannot open '" + path + "'");
    }
    h.is_render = false;
    int id = s_next_id++;
    int w = h.tex.width, hh = h.tex.height;
    s_images[id] = h;
    return makeHandle(id, w, hh);
}

// ── image.load_data(format, base64) ──────────────────────────────────────────

static Value img_load_data(Value* args, int argc) {
    if (argc < 2 || !args[0].isString() || !args[1].isString())
        throw std::runtime_error("image.load_data: expected format string and base64 string");
    std::string ext = args[0].asString();
    if (ext[0] != '.')
        ext = "." + ext;
    auto bytes = b64decode(args[1].asString());
    if (bytes.empty())
        throw std::runtime_error("image.load_data: empty or invalid base64 data");

    TexHandle h;
    h.tex = loadFromMemory(bytes, ext);
    h.is_render = false;
    int id = s_next_id++;
    int w = h.tex.width, hh = h.tex.height;
    s_images[id] = h;
    return makeHandle(id, w, hh);
}

// ── image.create(w, h) ───────────────────────────────────────────────────────

static Value img_create(Value* args, int argc) {
    int w = (int)numArg(args, argc, 0, "image.create");
    int h = (int)numArg(args, argc, 1, "image.create");
    TexHandle hnd;
    hnd.rtt = LoadRenderTexture(w, h);
    hnd.is_render = true;
    int id = s_next_id++;
    s_images[id] = hnd;
    return makeHandle(id, w, h);
}

// ── image.begin_draw(img) ────────────────────────────────────────────────────

static Value img_begin(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("image.begin_draw: expected image handle");
    int id = handleId(args[0], "image.begin_draw");
    TexHandle& h = findHandle(id, "image.begin_draw");
    if (!h.is_render)
        throw std::runtime_error("image.begin_draw: not a render texture — use image.create()");
    pixelsClose(h);
    BeginTextureMode(h.rtt);
    return Value{};
}

// ── image.end_draw() ─────────────────────────────────────────────────────────

static Value img_end(Value* args, int argc) {
    (void)args;
    (void)argc;
    EndTextureMode();
    return Value{};
}

// ── image.draw(img, x, y [, w, h [, tint]]) ──────────────────────────────────

static Value img_draw(Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("image.draw: expected img, x, y");
    int id = handleId(args[0], "image.draw");
    TexHandle& h = findHandle(id, "image.draw");
    pixelsClose(h);

    Texture2D tex = h.is_render ? h.rtt.texture : h.tex;
    float x = (float)numArg(args, argc, 1, "image.draw");
    float y = (float)numArg(args, argc, 2, "image.draw");
    float dw = argc > 3 ? (float)numArg(args, argc, 3, "image.draw") : (float)tex.width;
    float dh = argc > 4 ? (float)numArg(args, argc, 4, "image.draw") : (float)tex.height;
    Color tint = (argc > 5 && args[5].isMap()) ? toColor(args[5]) : WHITE;

    // RenderTexture2D has Y-axis flipped in OpenGL — negate src.height to correct
    float sh = h.is_render ? -(float)tex.height : (float)tex.height;
    Rectangle src = {0, 0, (float)tex.width, sh};
    Rectangle dst = {x, y, dw, dh};
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
    return Value{};
}

// ── image.unload(img) ────────────────────────────────────────────────────────

static Value img_unload(Value* args, int argc) {
    if (argc < 1)
        return Value{};
    int id = handleId(args[0], "image.unload");
    auto it = s_images.find(id);
    if (it == s_images.end())
        return Value{};
    TexHandle& h = it->second;
    if (h.pixels_open) {
        UnloadImage(h.cpu);
        h.pixels_open = false;
    }
    if (h.is_render)
        UnloadRenderTexture(h.rtt);
    else
        UnloadTexture(h.tex);
    s_images.erase(it);
    return Value{};
}

// ── image.begin_pixels(img) ──────────────────────────────────────────────────

static Value img_begin_pixels(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("image.begin_pixels: expected image handle");
    int id = handleId(args[0], "image.begin_pixels");
    pixelsOpen(findHandle(id, "image.begin_pixels"));
    return Value{};
}

// ── image.end_pixels(img) ────────────────────────────────────────────────────

static Value img_end_pixels(Value* args, int argc) {
    if (argc < 1)
        throw std::runtime_error("image.end_pixels: expected image handle");
    int id = handleId(args[0], "image.end_pixels");
    pixelsClose(findHandle(id, "image.end_pixels"));
    return Value{};
}

// ── image.get_pixel(img, x, y) ───────────────────────────────────────────────

static Value img_get_pixel(Value* args, int argc) {
    if (argc < 3)
        throw std::runtime_error("image.get_pixel: expected img, x, y");
    int id = handleId(args[0], "image.get_pixel");
    TexHandle& h = findHandle(id, "image.get_pixel");
    int x = (int)numArg(args, argc, 1, "image.get_pixel");
    int y = (int)numArg(args, argc, 2, "image.get_pixel");
    pixelsOpen(h);
    Color c = GetImageColor(h.cpu, x, y);
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("r")), Value(c.r / 255.0));
    m.mapSet(Value(std::string("g")), Value(c.g / 255.0));
    m.mapSet(Value(std::string("b")), Value(c.b / 255.0));
    m.mapSet(Value(std::string("a")), Value(c.a / 255.0));
    return m;
}

// ── image.set_pixel(img, x, y, color) ────────────────────────────────────────

static Value img_set_pixel(Value* args, int argc) {
    if (argc < 4)
        throw std::runtime_error("image.set_pixel: expected img, x, y, color");
    int id = handleId(args[0], "image.set_pixel");
    TexHandle& h = findHandle(id, "image.set_pixel");
    int x = (int)numArg(args, argc, 1, "image.set_pixel");
    int y = (int)numArg(args, argc, 2, "image.set_pixel");
    pixelsOpen(h);
    ImageDrawPixel(&h.cpu, x, y, toColor(args[3]));
    return Value{};
}

// ── image_draw_sprite ─────────────────────────────────────────────────────────

void image_draw_sprite(int id, float x, float y, float dw, float dh, unsigned char cr, unsigned char cg,
                       unsigned char cb, unsigned char ca) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        return;
    const TexHandle& h = it->second;

    Texture2D tex = h.is_render ? h.rtt.texture : h.tex;
    if (dw == 0.0f)
        dw = (float)tex.width;
    if (dh == 0.0f)
        dh = (float)tex.height;

    // RenderTexture2D has Y-axis flipped in OpenGL — negate src.height to correct
    float sh = h.is_render ? -(float)tex.height : (float)tex.height;
    Rectangle src = {0, 0, (float)tex.width, sh};
    Rectangle dst = {x, y, dw, dh};
    Color tint = {cr, cg, cb, ca};
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
}

// ── makeImageModule ───────────────────────────────────────────────────────────

Value makeImageModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("load")), Value::makeBuiltin(img_load));
    m.mapSet(Value(std::string("load_data")), Value::makeBuiltin(img_load_data));
    m.mapSet(Value(std::string("create")), Value::makeBuiltin(img_create));
    m.mapSet(Value(std::string("begin_draw")), Value::makeBuiltin(img_begin));
    m.mapSet(Value(std::string("end_draw")), Value::makeBuiltin(img_end));
    m.mapSet(Value(std::string("draw")), Value::makeBuiltin(img_draw));
    m.mapSet(Value(std::string("unload")), Value::makeBuiltin(img_unload));
    m.mapSet(Value(std::string("begin_pixels")), Value::makeBuiltin(img_begin_pixels));
    m.mapSet(Value(std::string("end_pixels")), Value::makeBuiltin(img_end_pixels));
    m.mapSet(Value(std::string("get_pixel")), Value::makeBuiltin(img_get_pixel));
    m.mapSet(Value(std::string("set_pixel")), Value::makeBuiltin(img_set_pixel));
    return m;
}
