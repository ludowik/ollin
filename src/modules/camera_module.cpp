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

static Value cam_open(CallCtx& ctx) {
    int w = ctx.argc >= 1 ? (int)numArg(ctx.args, 0, "camera.open") : 640;
    int h = ctx.argc >= 2 ? (int)numArg(ctx.args, 1, "camera.open") : 480;

    if (!s_cam_id || !image_tex_valid(s_cam_id) || s_cam_w != w || s_cam_h != h) {
        s_cam_w = w;
        s_cam_h = h;
        s_cam_handle = image_alloc_tex(w, h, &s_cam_id);
        // Forcer la réinitialisation JS si les dimensions changent (sinon cam.w/h restent
        // à l'ancienne valeur et HEAPU8.set copie des pixels en mauvais stride).
        EM_ASM({
            const cam = window.__ollinCam;
            if (!cam) return;
            if (cam.stream) cam.stream.getTracks().forEach(function(t) { t.stop(); });
            if (cam.video && cam.video.parentNode) cam.video.parentNode.removeChild(cam.video);
            cam.video = null; cam.stream = null; cam.state = 'idle';
        });
    }

    EM_ASM({
        var w = $0;
        var h = $1;
        if (!window.__ollinCam) window.__ollinCam = {};
        const cam = window.__ollinCam;
        if (cam.state === 'open' || cam.state === 'opening') return;
        cam.w = w; cam.h = h;
        cam.state = 'opening';
        const vid = document.createElement('video');
        vid.setAttribute('playsinline', 'playsinline');
        vid.setAttribute('autoplay', 'autoplay');
        vid.muted = true;
        vid.style.position = 'fixed';
        vid.style.top = '-9999px';
        vid.style.left = '-9999px';
        document.body.appendChild(vid);
        cam.video = vid;
        const cv = document.createElement('canvas');
        cv.width = w; cv.height = h;
        cam.canvas = cv;
        cam.ctx2d = cv.getContext('2d');
        navigator.mediaDevices.getUserMedia({ video: { width: w, height: h } })
            .then(function(stream) {
                cam.stream = stream;
                vid.srcObject = stream;
                return vid.play();
            })
            .then(function() { cam.state = 'open'; })
            .catch(function() { cam.state = 'error'; });
    }, w, h);

    return Value{};
}

static Value cam_capture(CallCtx&) {
    if (!s_cam_id || !image_tex_valid(s_cam_id))
        return Value{};

    std::vector<uint8_t> pixels((size_t)(s_cam_w * s_cam_h * 4));
    int ok = EM_ASM_INT({
        const cam = window.__ollinCam;
        if (!cam || cam.state !== 'open') return 0;
        const vid = cam.video;
        if (!vid || vid.readyState < 2) return 0;
        try {
            cam.ctx2d.drawImage(vid, 0, 0, cam.w, cam.h);
            const img = cam.ctx2d.getImageData(0, 0, cam.w, cam.h);
            HEAPU8.set(img.data, $0);
            return 1;
        } catch(e) { return 0; }
    }, pixels.data());

    if (!ok)
        return Value{};

    image_push_pixels(s_cam_id, pixels.data());
    return s_cam_handle;
}

static Value cam_close(CallCtx&) {
    EM_ASM({
        const cam = window.__ollinCam;
        if (!cam) return;
        if (cam.stream) cam.stream.getTracks().forEach(function(t) { t.stop(); });
        cam.stream = null;
        if (cam.video && cam.video.parentNode) cam.video.parentNode.removeChild(cam.video);
        cam.video = null;
        cam.state = 'idle';
    });
    return Value{};
}

static Value cam_is_open(CallCtx&) {
    int r = EM_ASM_INT({
        const cam = window.__ollinCam;
        return (cam && cam.state === 'open') ? 1 : 0;
    });
    return Value(int64_t(r));
}

Value makeCameraModule() {
    Value m = Value::makeMap();
    m.mapSet(Value(std::string("open")),    Value::makeBuiltin(cam_open));
    m.mapSet(Value(std::string("capture")), Value::makeBuiltin(cam_capture));
    m.mapSet(Value(std::string("close")),   Value::makeBuiltin(cam_close));
    m.mapSet(Value(std::string("isOpen")),  Value::makeBuiltin(cam_is_open));
    return m;
}
