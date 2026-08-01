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

// ── teinte globale (graphics.tint / noTint) ─────────────────────────────────────
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

// ── storage ───────────────────────────────────────────────────────────────────

struct TexHandle {
    int id = 0;
    bool is_render = false;
    bool is_streaming = false; // texture alimentée par image_push_pixels (caméra) → ombre CPU maintenue
    bool pixels_open = false;
    bool gpu_dirty = false;   // le GPU a été dessiné (beginDraw) → resync CPU au prochain accès pixel
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

// ── base64 decode ─────────────────────────────────────────────────────────────

static std::vector<uint8_t> b64decode(const std::string& s);
// Wrapper public (déclaré dans image_module.h) — réutilisé pour d'autres ressources.
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

// ── WASM interop ──────────────────────────────────────────────────────────────

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
            UnloadImage(h->cpu);   // mémoire CPU : toujours libérée (indépendante du GL)
        if (!gl)
            continue;              // fenêtre partie : sauter les appels GPU, PAS le free CPU
        if (h->is_render)
            UnloadRenderTexture(h->rtt);
        else
            UnloadTexture(h->tex);
    }
    s_images.clear();
    s_next_id = 1;
}

// ── helpers ───────────────────────────────────────────────────────────────────

static Value make_handle(int id, int w, int h, TexHandle* ptr) {
    static const Value K_ID(std::string("id")), K_WIDTH(std::string("width")), K_HEIGHT(std::string("height"));
    Value m = Value::make_map();
    m.mptr->userdata = ptr;
    m.map_set(K_ID, Value((int64_t)id));   // requis par graphics.sprite
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
        // Caméra : l'ombre CPU est maintenue à jour par image_push_pixels.
        if (!h.cpu.data)
            h.cpu = GenImageColor(h.tex.width, h.tex.height, BLANK);
    } else {
        // Image chargée (image.load) : lire les vrais pixels depuis le GPU au lieu de
        // générer du BLANK (sinon getPixel renvoie transparent et endPixels efface l'image).
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

// Extension (avec le point) déduite du chemin ; ".png" par défaut.
static std::string ext_of(const std::string& path) {
    auto dot = path.find_last_of('.');
    return dot == std::string::npos ? std::string(".png") : path.substr(dot);
}

#ifdef __EMSCRIPTEN__
// Récupère une ressource servie (même origine) de façon SYNCHRONE, pour garder
// image.load() synchrone. XHR synchrone sur le thread principal n'autorise pas
// responseType 'arraybuffer' → on lit responseText en binaire (x-user-defined).
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

// ── image.load(path) ──────────────────────────────────────────────────────────

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
        // Pas d'upload : tenter de récupérer la ressource servie (même origine),
        // relative à la page (ex. image.load("logo.png") → <base>/logo.png).
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

// ── image.loadData(format, base64) ──────────────────────────────────────────

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

// ── image.create(w, h) ───────────────────────────────────────────────────────

static int img_create(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.create";
    int w = (int)num_arg(args, argc, 0, FN);
    int h = (int)num_arg(args, argc, 1, FN);
    TexHandle hnd;
    hnd.rtt = LoadRenderTexture(w, h);
    hnd.is_render = true;
    // Ombre CPU PERSISTANTE (RGBA8) : source de vérité des pixels. Évite tout
    // glReadPixels en cours de frame (LoadImageFromTexture) — qui casse le rendu
    // WebGL/WASM (FBO courant perdu) — et accélère begin/setPixel/endPixels.
    hnd.cpu = GenImageColor(w, h, BLANK);
    UpdateTexture(hnd.rtt.texture, hnd.cpu.data);   // texture initiale = transparente
    int id = s_next_id++;
    hnd.id = id;
    auto uptr = std::make_unique<TexHandle>(std::move(hnd));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return ctx.ret(make_handle(id, w, h, ptr));
}

// ── image.beginDraw(img) ────────────────────────────────────────────────────

static int img_begin(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.beginDraw";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    TexHandle& h = handle_ptr(args[0], FN);
    if (!h.is_render)
        throw std::runtime_error(std::string(FN) + ": not a render texture — use image.create()");
    pixels_close(h);
    h.gpu_dirty = true;   // le dessin GPU va diverger de l'ombre CPU → resync au prochain accès pixel
    BeginTextureMode(h.rtt);
    return ctx.ret(Value{});
}

// ── image.endDraw() ─────────────────────────────────────────────────────────

static int img_end(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    EndTextureMode();
    return ctx.ret(Value{});
}

// ── image.draw(img, x, y [, w, h [, tint]]) ──────────────────────────────────

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
    // teinte : argument explicite prioritaire, sinon teinte globale (graphics.tint)
    Color tint = (argc > 5 && args[5].is_map()) ? to_color(args[5]) : (s_has_tint ? s_tint : WHITE);

    // RenderTexture2D has Y-axis flipped in OpenGL — negate src.height to correct
    float sh = h.is_render ? -(float)tex.height : (float)tex.height;
    Rectangle src = {0, 0, (float)tex.width, sh};
    Rectangle dst = {x, y, dw, dh};
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
    return ctx.ret(Value{});
}

// ── image.unload(img) ────────────────────────────────────────────────────────

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
        UnloadImage(h.cpu);   // ombre CPU persistante
    if (h.is_render)
        UnloadRenderTexture(h.rtt);
    else
        UnloadTexture(h.tex);
    s_images.erase(it);
    return ctx.ret(Value{});
}

// ── image.beginPixels(img) ──────────────────────────────────────────────────

static int img_begin_pixels(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.beginPixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixels_open(handle_ptr(args[0], FN));
    return ctx.ret(Value{});
}

// ── image.endPixels(img) ────────────────────────────────────────────────────

static int img_end_pixels(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    static constexpr const char* FN = "image.endPixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixels_close(handle_ptr(args[0], FN));
    return ctx.ret(Value{});
}

// ── image.getPixel(img, x, y) ───────────────────────────────────────────────

// Renvoie 4 valeurs (r, g, b, a) dans [0,1] : `var r, g, b, a = image.getPixel(img, x, y)`.
// Multi-retour direct dans les registres (aucune allocation de map par pixel) → chemin
// chaud du traitement pixel par pixel.
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
        c = BLANK; // hors image → transparent (borne x,y ; sinon accès OOB dans le chemin rapide)
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

// ── image.setPixel(img, x, y, color | r, g, b, a) ───────────────────────────

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
        return ctx.ret(Value{}); // hors image → ignore (borne x,y ; sinon écriture OOB dans le chemin rapide)
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

// ── image.mapPixel(img, f) ──────────────────────────────────────────────────

// Applique f(x, y, r, g, b, a) → r, g, b, a à chaque pixel (x,y entiers 0-based ;
// canaux [0,1]). beginPixels/endPixels sont gérés en interne. Les valeurs de retour
// manquantes ou non numériques laissent le canal d'origine inchangé.
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
                // lecture depuis l'ombre CPU courante (le callback a pu la muter au tour précédent)
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
                // écriture recalculée : le callback a pu réallouer/redimensionner h.cpu
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

// ── image_draw_sprite ─────────────────────────────────────────────────────────

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
    Rectangle dst = {x, y, dw, dh};
    Color tint = {cr, cg, cb, ca};
    DrawTexturePro(tex, src, dst, {0, 0}, 0.0f, tint);
}

// ── streaming texture (camera module) ────────────────────────────────────────

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

// ── makeImageModule ───────────────────────────────────────────────────────────

Value make_image_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("load")), Value::make_builtin(img_load));
    m.map_set(Value(std::string("loadData")), Value::make_builtin(img_load_data));
    m.map_set(Value(std::string("create")), Value::make_builtin(img_create));
    m.map_set(Value(std::string("beginDraw")), Value::make_builtin(img_begin));
    m.map_set(Value(std::string("endDraw")), Value::make_builtin(img_end));
    m.map_set(Value(std::string("draw")), Value::make_builtin(img_draw));
    m.map_set(Value(std::string("unload")), Value::make_builtin(img_unload));
    m.map_set(Value(std::string("beginPixels")), Value::make_builtin(img_begin_pixels));
    m.map_set(Value(std::string("endPixels")), Value::make_builtin(img_end_pixels));
    m.map_set(Value(std::string("getPixel")), Value::make_builtin(img_get_pixel));
    m.map_set(Value(std::string("setPixel")), Value::make_builtin(img_set_pixel));
    m.map_set(Value(std::string("mapPixel")), Value::make_builtin(img_map_pixel));
    return m;
}
