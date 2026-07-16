#include "image_module.h"
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
    bool pixels_open = false;
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
    std::string dotExt = (!ext.empty() && ext[0] == '.') ? ext : ("." + ext);
    image_preload(name, b64decode(b64), dotExt);
}

void image_reset() {
    for (auto& [id, h] : s_images) {
        if (!IsWindowReady())
            break;
        if (h->pixels_open) {
            UnloadImage(h->cpu);
        }
        if (h->is_render)
            UnloadRenderTexture(h->rtt);
        else
            UnloadTexture(h->tex);
    }
    s_images.clear();
    s_next_id = 1;
}

// ── helpers ───────────────────────────────────────────────────────────────────

static Value makeHandle(int id, int w, int h, TexHandle* ptr) {
    static const Value K_ID(std::string("id")), K_WIDTH(std::string("width")), K_HEIGHT(std::string("height"));
    Value m = Value::makeMap();
    m.mptr->userdata = ptr;
    m.mapSet(K_ID, Value((int64_t)id));   // requis par graphics.sprite
    m.mapSet(K_WIDTH, Value((int64_t)w));
    m.mapSet(K_HEIGHT, Value((int64_t)h));
    return m;
}

static TexHandle& handlePtr(const Value& v, const char* fn) {
    if (!v.isMap() || !v.mptr->userdata)
        throw std::runtime_error(std::string(fn) + ": expected image handle");
    return *(TexHandle*)v.mptr->userdata;
}

static Color toColor(const Value& v) {
    static const Value K_R(std::string("r")), K_G(std::string("g")), K_B(std::string("b")), K_A(std::string("a"));
    if (!v.isMap())
        throw std::runtime_error("image: expected Color object");
    auto gc = [&](const Value& k, double def) -> uint8_t {
        Value f = v.mapGet(k);
        return f.isNumber() ? (uint8_t)(f.asNum() * 255.0 + 0.5) : (uint8_t)(def * 255.0);
    };
    return {gc(K_R, 1), gc(K_G, 1), gc(K_B, 1), gc(K_A, 1)};
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
#ifdef __EMSCRIPTEN__
    // SONDE (diagnostic) : ce readback GPU→CPU est le SEUL transfert GL→mémoire du
    // moteur. Sur GPU réel (Windows/iOS), un format/taille inattendu ici trahirait
    // l'écriture hors-bornes recherchée (le rasteriseur logiciel de CI la masque).
    // On journalise tout écart dims/format/taille dans l'overlay (window.__ollinCrash)
    // et la console. Purement observationnel : aucun changement de comportement.
    {
        int tw = h.rtt.texture.width, th = h.rtt.texture.height;
        int expBytes = tw * th * 4;   // RGBA8 attendu (format des render textures raylib)
        int gotBytes = GetPixelDataSize(h.cpu.width, h.cpu.height, h.cpu.format);
        if (h.cpu.width != tw || h.cpu.height != th ||
            h.cpu.format != PIXELFORMAT_UNCOMPRESSED_R8G8B8A8 || gotBytes != expBytes) {
            EM_ASM(
                {
                    var m = "SONDE readback tex=" + $0 + "x" + $1 + " cpu=" + $2 + "x" + $3 + " fmt=" + $4 +
                            " got=" + $5 + "o exp=" + $6 + "o";
                    if (window.__ollinCrash)
                        window.__ollinCrash.noteStderr(m);
                    console.error(m);
                },
                tw, th, h.cpu.width, h.cpu.height, (int)h.cpu.format, gotBytes, expBytes);
        }
    }
#endif
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

// Extension (avec le point) déduite du chemin ; ".png" par défaut.
static std::string extOf(const std::string& path) {
    auto dot = path.find_last_of('.');
    return dot == std::string::npos ? std::string(".png") : path.substr(dot);
}

#ifdef __EMSCRIPTEN__
// Récupère une ressource servie (même origine) de façon SYNCHRONE, pour garder
// image.load() synchrone. XHR synchrone sur le thread principal n'autorise pas
// responseType 'arraybuffer' → on lit responseText en binaire (x-user-defined).
static std::vector<uint8_t> fetchBytesSync(const std::string& url) {
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

static Value img_load(Value* args, int argc) {
    if (argc < 1 || !args[0].isString())
        throw std::runtime_error("image.load: expected path string");
    const std::string& path = args[0].asString();

    TexHandle h;
    auto it = s_preloaded.find(path);
    if (it != s_preloaded.end()) {
        h.tex = loadFromMemory(it->second.first, it->second.second);
    } else {
#ifdef __EMSCRIPTEN__
        // Pas d'upload : tenter de récupérer la ressource servie (même origine),
        // relative à la page (ex. image.load("logo.png") → <base>/logo.png).
        std::vector<uint8_t> bytes = fetchBytesSync(path);
        if (!bytes.empty())
            h.tex = loadFromMemory(bytes, extOf(path));
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
    return makeHandle(id, w, hh, ptr);
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
    h.id = id;
    int w = h.tex.width, hh = h.tex.height;
    auto uptr = std::make_unique<TexHandle>(std::move(h));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return makeHandle(id, w, hh, ptr);
}

// ── image.create(w, h) ───────────────────────────────────────────────────────

static Value img_create(Value* args, int argc) {
    static constexpr const char* FN = "image.create";
    int w = (int)numArg(args, argc, 0, FN);
    int h = (int)numArg(args, argc, 1, FN);
    TexHandle hnd;
    hnd.rtt = LoadRenderTexture(w, h);
    hnd.is_render = true;
    int id = s_next_id++;
    hnd.id = id;
    auto uptr = std::make_unique<TexHandle>(std::move(hnd));
    TexHandle* ptr = uptr.get();
    s_images[id] = std::move(uptr);
    return makeHandle(id, w, h, ptr);
}

// ── image.begin_draw(img) ────────────────────────────────────────────────────

static Value img_begin(Value* args, int argc) {
    static constexpr const char* FN = "image.begin_draw";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    TexHandle& h = handlePtr(args[0], FN);
    if (!h.is_render)
        throw std::runtime_error(std::string(FN) + ": not a render texture — use image.create()");
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
    static constexpr const char* FN = "image.draw";
    if (argc < 3)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y");
    TexHandle& h = handlePtr(args[0], FN);
    pixelsClose(h);

    Texture2D tex = h.is_render ? h.rtt.texture : h.tex;
    float x = (float)numArg(args, 1, FN);
    float y = (float)numArg(args, 2, FN);
    float dw = argc > 3 ? (float)numArg(args, 3, FN) : (float)tex.width;
    float dh = argc > 4 ? (float)numArg(args, 4, FN) : (float)tex.height;
    // teinte : argument explicite prioritaire, sinon teinte globale (graphics.tint)
    Color tint = (argc > 5 && args[5].isMap()) ? toColor(args[5]) : (s_has_tint ? s_tint : WHITE);

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
    if (!args[0].isMap() || !args[0].mptr->userdata)
        return Value{};
    TexHandle& h = *(TexHandle*)args[0].mptr->userdata;
    auto it = s_images.find(h.id);
    if (it == s_images.end())
        return Value{};
    args[0].mptr->userdata = nullptr;
    if (h.pixels_open)
        UnloadImage(h.cpu);
    if (h.is_render)
        UnloadRenderTexture(h.rtt);
    else
        UnloadTexture(h.tex);
    s_images.erase(it);
    return Value{};
}

// ── image.begin_pixels(img) ──────────────────────────────────────────────────

static Value img_begin_pixels(Value* args, int argc) {
    static constexpr const char* FN = "image.begin_pixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixelsOpen(handlePtr(args[0], FN));
    return Value{};
}

// ── image.end_pixels(img) ────────────────────────────────────────────────────

static Value img_end_pixels(Value* args, int argc) {
    static constexpr const char* FN = "image.end_pixels";
    if (argc < 1)
        throw std::runtime_error(std::string(FN) + ": expected image handle");
    pixelsClose(handlePtr(args[0], FN));
    return Value{};
}

// ── image.get_pixel(img, x, y) ───────────────────────────────────────────────

static Value img_get_pixel(Value* args, int argc) {
    static constexpr const char* FN = "image.get_pixel";
    static const Value K_R(std::string("r")), K_G(std::string("g")), K_B(std::string("b")), K_A(std::string("a"));
    if (argc < 3)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y");
    TexHandle& h = handlePtr(args[0], FN);
    int x = (int)numArg(args, 1, FN);
    int y = (int)numArg(args, 2, FN);
    pixelsOpen(h);
    Color c;
    if (x < 0 || y < 0 || x >= h.cpu.width || y >= h.cpu.height) {
        c = BLANK; // hors image → transparent (borne x,y ; sinon accès OOB dans le chemin rapide)
    } else if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        const uint8_t* px = (const uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
        c = {px[0], px[1], px[2], px[3]};
    } else {
        c = GetImageColor(h.cpu, x, y);
    }
    Value m = Value::makeMap();
    m.mapSet(K_R, Value(c.r / 255.0));
    m.mapSet(K_G, Value(c.g / 255.0));
    m.mapSet(K_B, Value(c.b / 255.0));
    m.mapSet(K_A, Value(c.a / 255.0));
    return m;
}

// ── image.set_pixel(img, x, y, color | r, g, b, a) ───────────────────────────

static Value img_set_pixel(Value* args, int argc) {
    static constexpr const char* FN = "image.set_pixel";
    if (argc < 4)
        throw std::runtime_error(std::string(FN) + ": expected img, x, y, color");
    TexHandle& h = handlePtr(args[0], FN);
    int x = (int)numArg(args, 1, FN);
    int y = (int)numArg(args, 2, FN);
    pixelsOpen(h);
    if (x < 0 || y < 0 || x >= h.cpu.width || y >= h.cpu.height)
        return Value{}; // hors image → ignore (borne x,y ; sinon écriture OOB dans le chemin rapide)
    Color c = (argc >= 7) ? Color{
        (uint8_t)(numArg(args, 3, FN) * 255.0 + 0.5),
        (uint8_t)(numArg(args, 4, FN) * 255.0 + 0.5),
        (uint8_t)(numArg(args, 5, FN) * 255.0 + 0.5),
        (uint8_t)(numArg(args, 6, FN) * 255.0 + 0.5),
    } : toColor(args[3]);
    if (h.cpu.format == PIXELFORMAT_UNCOMPRESSED_R8G8B8A8) {
        uint8_t* px = (uint8_t*)h.cpu.data + (y * h.cpu.width + x) * 4;
        px[0] = c.r; px[1] = c.g; px[2] = c.b; px[3] = c.a;
    } else {
        ImageDrawPixel(&h.cpu, x, y, c);
    }
    return Value{};
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
