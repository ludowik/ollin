#include "image_module.h"
#include "../vm.h"
#include "modules/module_utils.h"
#include <cstdint>
#include <memory>
#include <raylib.h>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <cstdlib>
#include <emscripten.h>
#endif

static bool s_has_tint = false;
static Color s_tint = WHITE;

void image_set_tint(bool has, unsigned char r, unsigned char g, unsigned char b, unsigned char a) {
    s_has_tint = has;
    s_tint = {r, g, b, a};
}

void image_get_tint(bool* has, unsigned char* r, unsigned char* g, unsigned char* b, unsigned char* a) {
    *has = s_has_tint;
    *r = s_tint.r;
    *g = s_tint.g;
    *b = s_tint.b;
    *a = s_tint.a;
}

static int s_sprite_mode = SPRITE_CORNER;

void image_set_sprite_mode(int mode) {
    s_sprite_mode = mode;
}

int image_get_sprite_mode() {
    return s_sprite_mode;
}

// Destination rectangle for the current anchoring. The offset applies to the DESTINATION size
// (dw/dh, already resolved): centring an image drawn at 200x200 shifts it by 100, whatever the
// source size.
static Rectangle sprite_dest(float x, float y, float dw, float dh) {
    if (s_sprite_mode == SPRITE_CENTER) {
        x -= dw * 0.5f;
        y -= dh * 0.5f;
    }
    return {x, y, dw, dh};
}


struct TexHandle {
    int id = 0;
    bool is_render = false;
    bool is_streaming = false; // a texture fed by image_push_pixels (the camera), so the CPU shadow is kept up to date
    bool pixels_open = false;
    bool gpu_dirty = false;   // the GPU was drawn into (beginDraw), so the CPU is resynced on the next pixel access
    Texture2D tex = {};
    RenderTexture2D rtt = {};
    Image cpu = {};
};

static std::unordered_map<int, std::unique_ptr<TexHandle>> s_images;
static int s_next_id = 1;

unsigned int image_gl_texid(int id) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        return 0;
    const TexHandle& h = *it->second;
    return h.is_render ? h.rtt.texture.id : h.tex.id;
}

// preloaded bytes: name → (bytes, ext with dot e.g. ".png")
static std::unordered_map<std::string, std::pair<std::vector<uint8_t>, std::string>> s_preloaded;


static std::vector<uint8_t> b64decode(const std::string& s);
// Public wrapper (declared in image_module.h), reused for other resources.
std::vector<uint8_t> image_b64_decode(const std::string& b64) {
    return b64decode(b64);
}

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

std::string image_b64_encode(const uint8_t* data, size_t len) {
    static const char* T = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    out.reserve((len + 2) / 3 * 4);
    for (size_t i = 0; i < len; i += 3) {
        uint32_t n = (uint32_t)data[i] << 16;
        size_t rest = len - i;
        if (rest > 1)
            n |= (uint32_t)data[i + 1] << 8;
        if (rest > 2)
            n |= (uint32_t)data[i + 2];
        out.push_back(T[(n >> 18) & 63]);
        out.push_back(T[(n >> 12) & 63]);
        out.push_back(rest > 1 ? T[(n >> 6) & 63] : '=');
        out.push_back(rest > 2 ? T[n & 63] : '=');
    }
    return out;
}


void image_preload(const std::string& name, const std::vector<uint8_t>& bytes, const std::string& ext) {
    s_preloaded[name] = {bytes, ext};
}

void image_preload_b64(const std::string& name, const std::string& b64, const std::string& ext) {
    std::string dot_ext = (!ext.empty() && ext[0] == '.') ? ext : ("." + ext);
    image_preload(name, b64decode(b64), dot_ext);
}

void image_reset() {
    bool gl = IsWindowReady();
    for (auto& [id, h] : s_images) {
        if (h->cpu.data)
            UnloadImage(h->cpu);   // CPU memory is always freed, being independent of GL
        if (!gl)
            continue;              // the window is gone: skip the GPU calls, but NOT the CPU free
        if (h->is_render)
            UnloadRenderTexture(h->rtt);
        else
            UnloadTexture(h->tex);
    }
    s_images.clear();
    s_next_id = 1;
}


static Value make_handle(int id, int w, int h, TexHandle* ptr) {
    static const Value K_ID(std::string("id")), K_WIDTH(std::string("width")), K_HEIGHT(std::string("height"));
    Value m = Value::make_map();
    m.mptr->userdata = ptr;
    m.map_set(K_ID, Value((int64_t)id));   // required by graphics.sprite
    m.map_set(K_WIDTH, Value((int64_t)w));
    m.map_set(K_HEIGHT, Value((int64_t)h));
    return m;
}

static TexHandle& handle_ptr(const Value& v, const char* fn) {
    if (!v.is_map() || !v.mptr->userdata)
        throw std::runtime_error(std::string(fn) + ": expected image handle");
    return *(TexHandle*)v.mptr->userdata;
}

static Color to_color(const Value& v) {
    static const Value K_R(std::string("r")), K_G(std::string("g")), K_B(std::string("b")), K_A(std::string("a"));
    if (!v.is_map())
        throw std::runtime_error("image: expected Color object");
    auto gc = [&](const Value& k, double def) -> uint8_t {
        Value f = v.map_get(k);
        return f.is_number() ? (uint8_t)(f.as_num() * 255.0 + 0.5) : (uint8_t)(def * 255.0);
    };
    return {gc(K_R, 1), gc(K_G, 1), gc(K_B, 1), gc(K_A, 1)};
}

static void pixels_open(TexHandle& h) {
    if (h.pixels_open)
        return;
    if (h.is_render) {
        if (h.gpu_dirty) {
            Image fresh = LoadImageFromTexture(h.rtt.texture);
            if (fresh.data) {
                if (h.cpu.data) UnloadImage(h.cpu);
                h.cpu = fresh;
            }
            h.gpu_dirty = false;
        }
        if (!h.cpu.data)
            h.cpu = GenImageColor(h.rtt.texture.width, h.rtt.texture.height, BLANK);
    } else if (h.is_streaming) {
        // Camera: the CPU shadow is kept up to date by image_push_pixels.
        if (!h.cpu.data)
            h.cpu = GenImageColor(h.tex.width, h.tex.height, BLANK);
    } else {
        // A loaded image (image.load): read the real pixels back from the GPU instead of
        // generating BLANK, otherwise getPixel returns transparent and endPixels erases the
        // image.
        if (!h.cpu.data) {
            Image fresh = LoadImageFromTexture(h.tex);
            if (!fresh.data)
                throw std::runtime_error("image: pixel access failed (texture not readable)");
            h.cpu = fresh;
        }
    }
    h.pixels_open = true;
}

static void pixels_close(TexHandle& h) {
    if (!h.pixels_open)
        return;
    if (h.is_render)
        UpdateTexture(h.rtt.texture, h.cpu.data);
    else
        UpdateTexture(h.tex, h.cpu.data);
    h.pixels_open = false;
}

static Texture2D load_from_memory(const std::vector<uint8_t>& bytes, const std::string& ext) {
    Image img = LoadImageFromMemory(ext.c_str(), bytes.data(), (int)bytes.size());
    if (!img.data)
        throw std::runtime_error("image: failed to decode image (ext: " + ext + ")");
    Texture2D tex = LoadTextureFromImage(img);
    UnloadImage(img);
    return tex;
}

// Extension, dot included, taken from the path; ".png" by default.
static std::string ext_of(const std::string& path) {
    auto dot = path.find_last_of('.');
    return dot == std::string::npos ? std::string(".png") : path.substr(dot);
}

#ifdef __EMSCRIPTEN__
// Fetches a served, same-origin resource SYNCHRONOUSLY, to keep image.load() synchronous. A
// synchronous XHR on the main thread does not allow responseType 'arraybuffer', so responseText is
// read as binary through x-user-defined.
static std::vector<uint8_t> fetch_bytes_sync(const std::string& url) {
    int len = 0;
    char* data = (char*)EM_ASM_INT(
        {
            try {
                var u = UTF8ToString($0);
                var xhr = new XMLHttpRequest();
                xhr.open('GET', u, false);
                xhr.overrideMimeType('text/plain; charset=x-user-defined');
                xhr.send(null);
                if (xhr.status !== 200 && xhr.status !== 0)
                    return 0;
                var s = xhr.responseText;
                var n = s.length;
                var ptr = _malloc(n);
                for (var i = 0; i < n; i++)
                    HEAPU8[ptr + i] = s.charCodeAt(i) & 0xff;
                HEAP32[$1 >> 2] = n;
                return ptr;
            } catch (e) {
                return 0;
            }
        },
        url.c_str(), &len);
    std::vector<uint8_t> out;
    if (data && len > 0) {
        out.assign((uint8_t*)data, (uint8_t*)data + len);
        free(data);
    }
    return out;
}
#endif


static int img_load(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1 || !args[0].is_string())
        throw std::runtime_error("image.load: expected path string");
    const std::string& path = args[0].as_string();

    TexHandle h;
    auto it = s_preloaded.find(path);
    if (it != s_preloaded.end()) {
        h.tex = load_from_memory(it->second.first, it->second.second);
    } else {
#ifdef __EMSCRIPTEN__
        // Nothing was uploaded, so try to fetch the served, same-origin resource relative to the
        // page — image.load("logo.png") reads <base>/logo.png.
        std::vector<uint8_t> bytes = fetch_bytes_sync(path);
        if (!bytes.empty())
            h.tex = load_from_memory(bytes, ext_of(path));
#else
        h.tex = LoadTexture(path.c_str());
#endif
        if (h.tex.id == 0)
            throw std::runtime_error("image.load: cannot open '" + path + "'");
    }
    h.is_render = false;
    int id = s_next_id++;
    h.id = id;
    int w = h.tex.width, hh = h.tex.height;
    auto uptr = std::make_unique<TexHandle>(std::move(h));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return ctx.ret(make_handle(id, w, hh, ptr));
}


static int img_load_data(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 2 || !args[0].is_string() || !args[1].is_string())
        throw std::runtime_error("image.loadData: expected format string and base64 string");
    std::string ext = args[0].as_string();
    if (ext[0] != '.')
        ext = "." + ext;
    auto bytes = b64decode(args[1].as_string());
    if (bytes.empty())
        throw std::runtime_error("image.loadData: empty or invalid base64 data");

    TexHandle h;
    h.tex = load_from_memory(bytes, ext);
    h.is_render = false;
    int id = s_next_id++;
    h.id = id;
    int w = h.tex.width, hh = h.tex.height;
    auto uptr = std::make_unique<TexHandle>(std::move(h));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return ctx.ret(make_handle(id, w, hh, ptr));
}


static int img_create(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.create";
    int w = (int)num_arg(args, argc, 0, FN);
    int h = (int)num_arg(args, argc, 1, FN);
    TexHandle hnd;
    hnd.rtt = LoadRenderTexture(w, h);
    hnd.is_render = true;
    // A PERSISTENT CPU shadow (RGBA8), the source of truth for the pixels. It avoids any
    // mid-frame glReadPixels through LoadImageFromTexture — which breaks WebGL/WASM rendering by
    // losing the current FBO — and speeds up begin/setPixel/endPixels.
    hnd.cpu = GenImageColor(w, h, BLANK);
    UpdateTexture(hnd.rtt.texture, hnd.cpu.data);   // the initial texture is transparent
    int id = s_next_id++;
    hnd.id = id;
    auto uptr = std::make_unique<TexHandle>(std::move(hnd));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return ctx.ret(make_handle(id, w, h, ptr));
}


static int img_begin(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.beginDraw";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    TexHandle& h = handle_ptr(args[0], FN);
    if (!h.is_render)
        throw std::runtime_error(std::string(FN) + ": not a render texture — use image.create()");
    pixels_close(h);
    h.gpu_dirty = true;   // the GPU drawing will diverge from the CPU shadow, so it resyncs on the next pixel access
    BeginTextureMode(h.rtt);
    return ctx.ret(Value{});
}


static int img_end(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    EndTextureMode();
    return ctx.ret(Value{});
}


static int img_draw(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.draw";
    if (argc < 3)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y");
    TexHandle& h = handle_ptr(args[0], FN);
    pixels_close(h);

    Texture2D tex = h.is_render ? h.rtt.texture : h.tex;
    float x = (float)num_arg(args, 1, FN);
    float y = (float)num_arg(args, 2, FN);
    float dw = argc > 3 ? (float)num_arg(args, 3, FN) : (float)tex.width;
    float dh = argc > 4 ? (float)num_arg(args, 4, FN) : (float)tex.height;
    // the tint: an explicit argument wins, otherwise the global one (graphics.tint)
    Color tint = (argc > 5 && args[5].is_map()) ? to_color(args[5]) : (s_has_tint ? s_tint : WHITE);

    // RenderTexture2D has Y-axis flipped in OpenGL — negate src.height to correct
    float sh = h.is_render ? -(float)tex.height : (float)tex.height;
    Rectangle src = {0, 0, (float)tex.width, sh};
    Rectangle dst = sprite_dest(x, y, dw, dh);
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
    return ctx.ret(Value{});
}


static int img_unload(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    if (argc < 1)
        return ctx.ret(Value{});
    if (!args[0].is_map() || !args[0].mptr->userdata)
        return ctx.ret(Value{});
    TexHandle& h = *(TexHandle*)args[0].mptr->userdata;
    auto it = s_images.find(h.id);
    if (it == s_images.end())
        return ctx.ret(Value{});
    args[0].mptr->userdata = nullptr;
    if (h.cpu.data)
        UnloadImage(h.cpu);   // the persistent CPU-side copy
    if (h.is_render)
        UnloadRenderTexture(h.rtt);
    else
        UnloadTexture(h.tex);
    s_images.erase(it);
    return ctx.ret(Value{});
}


static int img_begin_pixels(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.beginPixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixels_open(handle_ptr(args[0], FN));
    return ctx.ret(Value{});
}


static int img_end_pixels(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.endPixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixels_close(handle_ptr(args[0], FN));
    return ctx.ret(Value{});
}


// Returns four values (r, g, b, a) in [0,1]: `var r, g, b, a = image.getPixel(img, x, y)`. The
// multi-return goes straight into the registers, with no map allocated per pixel, which matters on
// the hot path of pixel-by-pixel processing.
static int img_get_pixel(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.getPixel";
    if (argc < 3)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y");
    TexHandle& h = handle_ptr(args[0], FN);
    int x = (int)num_arg(args, 1, FN);
    int y = (int)num_arg(args, 2, FN);
    pixels_open(h);
    Color c;
    if (x < 0 || y < 0 || x >= h.cpu.width || y >= h.cpu.height) {
        c = BLANK; // outside the image is transparent; x and y are clamped, or the fast path would read out of bounds
    } else if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        const uint8_t* px = (const uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
        c = {px[0], px[1], px[2], px[3]};
    } else {
        c = GetImageColor(h.cpu, x, y);
    }
    ctx.set_result(0, Value(c.r / 255.0));
    ctx.set_result(1, Value(c.g / 255.0));
    ctx.set_result(2, Value(c.b / 255.0));
    ctx.set_result(3, Value(c.a / 255.0));
    return 4;
}


static int img_set_pixel(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.setPixel";
    if (argc < 4)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y, color");
    TexHandle& h = handle_ptr(args[0], FN);
    int x = (int)num_arg(args, 1, FN);
    int y = (int)num_arg(args, 2, FN);
    pixels_open(h);
    if (x < 0 || y < 0 || x >= h.cpu.width || y >= h.cpu.height)
        return ctx.ret(Value{}); // outside the image is ignored; x and y are clamped, or the fast path would write out of bounds
    Color c = (argc >= 7) ? Color{
        (uint8_t)(num_arg(args, 3, FN) * 255.0 + 0.5),
        (uint8_t)(num_arg(args, 4, FN) * 255.0 + 0.5),
        (uint8_t)(num_arg(args, 5, FN) * 255.0 + 0.5),
        (uint8_t)(num_arg(args, 6, FN) * 255.0 + 0.5),
    } : to_color(args[3]);
    if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        uint8_t* px = (uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
        px[0] = c.r; px[1] = c.g; px[2] = c.b; px[3] = c.a;
    } else {
        ImageDrawPixel(&h.cpu, x, y, c);
    }
    return ctx.ret(Value{});
}


// Applies f(x, y, r, g, b, a) -> r, g, b, a to every pixel, with x and y 0-based integers and the
// channels in [0,1]. beginPixels and endPixels are handled internally. A missing or non-numeric
// return value leaves the original channel untouched.
static int img_map_pixel(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.mapPixel";
    if (argc < 2)
        throw std::runtime_error(std::string(FN) + ": expected img, fn");
    TexHandle& h = handle_ptr(args[0], FN);
    Value fn = args[1];
    if (!fn.is_builtin() && !fn.is_func_val() && !fn.is_closure())
        throw std::runtime_error(std::string(FN) + ": second argument must be a function");
    pixels_open(h);
    VM* vm = ctx.vm;
    const int w = h.cpu.width;
    const int hgt = h.cpu.height;
    try {
        for (int y = 0; y < hgt; ++y) {
            for (int x = 0; x < w; ++x) {
                // read from the current CPU shadow: the callback may have mutated it last turn
                Color c;
                if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 && x < h.cpu.width && y < h.cpu.height) {
                    const uint8_t* px = (const uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
                    c = {px[0], px[1], px[2], px[3]};
                } else {
                    c = GetImageColor(h.cpu, x, y);
                }
                Value in[6] = {Value((int64_t)x),   Value((int64_t)y),   Value(c.r / 255.0),
                               Value(c.g / 255.0), Value(c.b / 255.0), Value(c.a / 255.0)};
                Value out[4];
                int n = vm->call_value_multi(fn, in, 6, out, 4);
                uint8_t ch[4] = {c.r, c.g, c.b, c.a};
                for (int i = 0; i < n; ++i)
                    if (out[i].is_number())
                        ch[i] = (uint8_t)(out[i].as_num() * 255.0 + 0.5);
                Color nc = {ch[0], ch[1], ch[2], ch[3]};
                // recompute the write target: the callback may have reallocated or resized h.cpu
                if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 && x < h.cpu.width && y < h.cpu.height) {
                    uint8_t* px = (uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
                    px[0] = nc.r; px[1] = nc.g; px[2] = nc.b; px[3] = nc.a;
                } else {
                    ImageDrawPixel(&h.cpu, x, y, nc);
                }
            }
        }
    } catch (...) {
        pixels_close(h);
        throw;
    }
    pixels_close(h);
    return ctx.ret(Value{});
}


void image_draw_sprite(int id, float x, float y, float dw, float dh, unsigned char cr, unsigned char cg,
                       unsigned char cb, unsigned char ca) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        return;
    const TexHandle& h = *it->second;

    Texture2D tex = h.is_render ? h.rtt.texture : h.tex;
    if (dw == 0.0f)
        dw = (float)tex.width;
    if (dh == 0.0f)
        dh = (float)tex.height;

    // RenderTexture2D has Y-axis flipped in OpenGL — negate src.height to correct
    float sh = h.is_render ? -(float)tex.height : (float)tex.height;
    Rectangle src = {0, 0, (float)tex.width, sh};
    Rectangle dst = sprite_dest(x, y, dw, dh);
    Color tint = {cr, cg, cb, ca};
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
}


Value image_alloc_tex(int w, int h, int* id_out) {
    Image blank = GenImageColor(w, h, BLANK);
    Texture2D tex = LoadTextureFromImage(blank);
    UnloadImage(blank);
    TexHandle hnd;
    hnd.tex = tex;
    hnd.is_render = false;
    hnd.is_streaming = true;
    hnd.cpu = GenImageColor(w, h, BLANK);
    int id = s_next_id++;
    hnd.id = id;
    *id_out = id;
    auto uptr = std::make_unique<TexHandle>(std::move(hnd));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return make_handle(id, w, h, ptr);
}

void image_push_pixels(int id, const uint8_t* rgba) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        return;
    TexHandle& h = *it->second;
    if (h.cpu.data)
        memcpy(h.cpu.data, rgba, (size_t)h.tex.width * (size_t)h.tex.height * 4);
    UpdateTexture(h.tex, rgba);
}

bool image_tex_valid(int id) {
    return s_images.count(id) > 0;
}

void image_free_tex(int id) {
    auto it = s_images.find(id);
    if (it == s_images.end())
        return;
    TexHandle& h = *it->second;
    if (h.cpu.data)
        UnloadImage(h.cpu);
    if (h.is_render)
        UnloadRenderTexture(h.rtt);
    else
        UnloadTexture(h.tex);
    s_images.erase(it);
}


Value make_image_module() {
    return MapBuilder()
        .fn("load", img_load)
        .fn("loadData", img_load_data)
        .fn("create", img_create)
        .fn("beginDraw", img_begin)
        .fn("endDraw", img_end)
        .fn("draw", img_draw)
        .fn("unload", img_unload)
        .fn("beginPixels", img_begin_pixels)
        .fn("endPixels", img_end_pixels)
        .fn("getPixel", img_get_pixel)
        .fn("setPixel", img_set_pixel)
        .fn("mapPixel", img_map_pixel)
        .done();
}
