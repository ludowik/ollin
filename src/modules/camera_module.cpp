#include "camera_module.h"
#include "image_module.h"
#include "modules/module_utils.h"
#include <emscripten.h>
#include <stdexcept>
#include <vector>

static int   s_cam_id = 0;
static Value s_cam_handle;
static int   s_cam_w = 0;
static int   s_cam_h = 0;

static void cam_reset_js() {
    EM_ASM({
        const cam = window.__ollinCam;
        if (!cam) return;
        if (cam.stream) cam.stream.get_tracks().for_each(function(t) { t.stop(); });
        if (cam.video && cam.video.parent_node) cam.video.parent_node.remove_child(cam.video);
        cam.video = null; cam.stream = null; cam.state = 'idle';
    });
}

void camera_reset() {
    cam_reset_js();
    s_cam_id = 0;
    s_cam_w = 0;
    s_cam_h = 0;
    s_cam_handle = Value{};
}

static int cam_open(CallCtx& ctx) {
    int w = ctx.argc >= 1 ? (int)num_arg(ctx.args, 0, "camera.open") : 640;
    int h = ctx.argc >= 2 ? (int)num_arg(ctx.args, 1, "camera.open") : 480;

    if (!s_cam_id || !image_tex_valid(s_cam_id) || s_cam_w != w || s_cam_h != h) {
        if (s_cam_id)
            image_free_tex(s_cam_id); // libère l'ancienne texture avant réalloc (sinon fuite GPU)
        s_cam_w = w;
        s_cam_h = h;
        s_cam_handle = image_alloc_tex(w, h, &s_cam_id);
    }

    EM_ASM({
        var w = $0;
        var h = $1;
        if (!window.__ollinCam) window.__ollinCam = {};
        const cam = window.__ollinCam;
        if (cam.state === 'open' || cam.state === 'opening') return;
        // Garde avant toute création DOM : sinon chaque retry en contexte non sécurisé
        // (état 'error') ajouterait un <video> orphelin de plus.
        if (!navigator.media_devices || !navigator.media_devices.get_user_media) {
            cam.state = 'error'; // contexte non sécurisé (HTTP hors localhost) → pas d'API caméra
            return;
        }
        cam.w = w; cam.h = h;
        cam.state = 'opening';
        const vid = document.create_element('video');
        vid.set_attribute('playsinline', 'playsinline');
        vid.set_attribute('autoplay', 'autoplay');
        vid.muted = true;
        vid.style.position = 'fixed';
        vid.style.top = '-9999px';
        vid.style.left = '-9999px';
        document.body.append_child(vid);
        cam.video = vid;
        navigator.media_devices.get_user_media({ video: { width: w, height: h } })
            .then(function(stream) {
                cam.stream = stream;
                vid.src_object = stream;
                return vid.play();
            })
            .then(function() { cam.state = 'open'; })
            .catch(function() { cam.state = 'error'; });
    }, w, h);

    return ctx.ret(Value{});
}

static int cam_capture(CallCtx& ctx) {
    if (!s_cam_id || !image_tex_valid(s_cam_id))
        return ctx.ret(Value{});

    // Buffer persistant réutilisé entre frames (chemin chaud, ~60 fps) : évite d'allouer
    // ~1,2 Mo par capture. Redimensionné seulement si la résolution change.
    static std::vector<uint8_t> pixels;
    size_t need = (size_t)s_cam_w * (size_t)s_cam_h * 4;
    if (pixels.size() != need)
        pixels.resize(need);
    int ok = EM_ASM_INT({
        const cam = window.__ollinCam;
        if (!cam || cam.state !== 'open') return 0;
        const vid = cam.video;
        if (!vid || vid.ready_state < 2) return 0;
        try {
            const w = $1; const h = $2;
            if (!cam.canvas || cam.canvas.width !== w || cam.canvas.height !== h) {
                cam.canvas = document.create_element('canvas');
                cam.canvas.width = w;
                cam.canvas.height = h;
                cam.ctx2d = cam.canvas.get_context('2d');
            }
            cam.ctx2d.draw_image(vid, 0, 0, w, h);
            const img = cam.ctx2d.get_image_data(0, 0, w, h);
            HEAPU8.set(img.data, $0);
            return 1;
        } catch(e) { return 0; }
    }, pixels.data(), s_cam_w, s_cam_h);

    if (!ok)
        return ctx.ret(Value{});

    image_push_pixels(s_cam_id, pixels.data());
    return ctx.ret(s_cam_handle);
}

static int cam_close(CallCtx& ctx) {
    cam_reset_js();
    return ctx.ret(Value{});
}

static int cam_is_open(CallCtx& ctx) {
    int r = EM_ASM_INT({
        const cam = window.__ollinCam;
        return (cam && cam.state === 'open') ? 1 : 0;
    });
    return ctx.ret(Value(int64_t(r)));
}

Value make_camera_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("open")),    Value::make_builtin(cam_open));
    m.map_set(Value(std::string("capture")), Value::make_builtin(cam_capture));
    m.map_set(Value(std::string("close")),   Value::make_builtin(cam_close));
    m.map_set(Value(std::string("isOpen")),  Value::make_builtin(cam_is_open));
    return m;
}
