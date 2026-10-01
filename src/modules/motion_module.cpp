#include "motion_module.h"
#include "graphics_quat.h"
#include "module_utils.h"
#include "value.h"
#include "vm.h"
#include <raymath.h>
#include <cmath>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// The motion sensors, build WITH raylib. raylib has no sensor API, so the readings come from the
// browser's DeviceOrientationEvent and DeviceMotionEvent; outside the browser the state is
// "unsupported" and every reading is zero.
//
// Three decisions explain the shape of the module:
//
// 1. The tilt is derived from the direction of UP in the device frame, which the spec fixes from beta
//    and gamma alone: (-cos b sin g, sin b, cos b cos g). No alpha, hence no compass and no arbitrary
//    yaw reference; and no platform-specific sign for a raw accelerometer. The gravity vector is that
//    direction times g.
//
// 2. The roll is read from the sideways component of UP in the SCREEN frame, asin(-up.x): turning the
//    phone like a steering wheel and tipping it like a tray both move that component by sin(angle),
//    whatever the phone's tilt towards or away from the user (a rotation about the user's forward
//    axis leaves the screen's own horizontal axis horizontal). A roll taken as atan2 of two
//    components, by contrast, is undefined for a phone held flat and flips sign past the vertical.
//
// 3. Angles are in the frame of the SCREEN, not of the device: the device frame is fixed to the
//    phone's natural portrait, so a phone held in landscape would swap its axes and turn left into
//    right depending on which way the screen was rotated. screen.orientation.angle (or the older
//    window.orientation) says by how much, and every reading is rotated by it.

namespace {

enum State { ST_OFF = 0, ST_PENDING = 1, ST_ON = 2, ST_DENIED = 3, ST_UNSUPPORTED = 4 };

constexpr double k_gravity = 9.80665;
constexpr double k_rad = 3.14159265358979323846 / 180.0;

struct Reading {
    int state = ST_OFF;
    double roll = 0.0;
    double pitch = 0.0;
    double gravity[3] = {0.0, 0.0, 0.0};
    double acceleration[3] = {0.0, 0.0, 0.0};
    bool has_attitude = false;
    Quaternion attitude = {0.0f, 0.0f, 0.0f, 1.0f};
};

Reading s_cur;

// What the JavaScript side hands over each frame: alpha, beta, gamma, the acceleration x y z, then
// the screen's rotation angle.
double s_raw[7];

const char* state_name(int state) {
    switch (state) {
    case ST_PENDING:
        return "pending";
    case ST_ON:
        return "on";
    case ST_DENIED:
        return "denied";
    case ST_UNSUPPORTED:
        return "unsupported";
    default:
        return "off";
    }
}

#ifdef __EMSCRIPTEN__
// Listeners are installed ONCE and outlive the program (a permission is the page's, not the
// program's). Written as plain statements: EM_ASM is a MACRO, so a comma outside parentheses would
// split its arguments.
//
// iOS 13+ makes both event classes ask for a permission, and only accepts the request from inside a
// user gesture. enable() therefore RECORDS the wish, and the first gesture after it asks. Elsewhere
// no permission exists and the listeners go up at once.
//
// A desktop browser defines the events but fires one with null angles and nothing after: that first
// null reading is what says "unsupported". A browser that fires nothing at all stays "pending".
void install_watch() {
    static bool installed = false;
    if (installed)
        return;
    installed = true;
    EM_ASM({
        if (window.__ollinMotion)
            return;
        var M = {};
        window.__ollinMotion = M;
        M.wanted = false;
        M.perm = 0;
        M.listening = false;
        M.seen = 0;
        M.o = new Float64Array(3);
        M.a = new Float64Array(3);
        M.onOrientation = function(e) {
            if (e.beta === null || e.gamma === null) {
                if (M.seen === 0)
                    M.seen = 2;
                return;
            }
            M.seen = 1;
            M.o[0] = e.alpha === null ? 0 : e.alpha;
            M.o[1] = e.beta;
            M.o[2] = e.gamma;
        };
        M.onMotion = function(e) {
            var a = e.acceleration;
            if (a) {
                M.a[0] = a.x || 0;
                M.a[1] = a.y || 0;
                M.a[2] = a.z || 0;
            }
        };
        M.listen = function() {
            if (M.listening)
                return;
            M.listening = true;
            window.addEventListener('deviceorientation', M.onOrientation);
            window.addEventListener('devicemotion', M.onMotion);
        };
        M.ask = function() {
            var O = window.DeviceOrientationEvent;
            var D = window.DeviceMotionEvent;
            if (!O || typeof O.requestPermission !== 'function') {
                M.perm = 2;
                M.listen();
                return;
            }
            M.perm = 1;
            var p1 = O.requestPermission();
            var p2 = Promise.resolve('granted');
            if (D && typeof D.requestPermission === 'function')
                p2 = D.requestPermission();
            Promise.all([p1, p2]).then(function(r) {
                if (r[0] === 'granted' && r[1] === 'granted') {
                    M.perm = 2;
                    M.listen();
                } else {
                    M.perm = 3;
                }
            }).catch(function() {
                M.perm = 3;
            });
        };
        M.enable = function() {
            M.wanted = true;
            if (M.perm !== 0)
                return;
            var O = window.DeviceOrientationEvent;
            if (!O || !window.isSecureContext) {
                M.perm = 4;
                return;
            }
            if (typeof O.requestPermission !== 'function')
                M.ask();
        };
        M.gesture = function() {
            if (M.wanted && M.perm === 0)
                M.ask();
        };
        M.state = function() {
            if (!M.wanted)
                return 0;
            if (M.perm === 4)
                return 4;
            if (M.perm === 3)
                return 3;
            if (M.seen === 1)
                return 2;
            if (M.seen === 2)
                return 4;
            return 1;
        };
        var opt = { capture: true };
        opt.passive = true;
        var names = 'pointerup touchend click keydown'.split(' ');
        for (var i = 0; i < names.length; i++)
            document.addEventListener(names[i], M.gesture, opt);
    });
}

int sample_raw() {
    return EM_ASM_INT({
        var M = window.__ollinMotion;
        if (!M)
            return 0;
        var base = $0 >> 3;
        for (var i = 0; i < 3; i++) {
            HEAPF64[base + i] = M.o[i];
            HEAPF64[base + 3 + i] = M.a[i];
        }
        var ang = 0;
        if (window.screen && screen.orientation && typeof screen.orientation.angle === 'number')
            ang = screen.orientation.angle;
        else if (typeof window.orientation === 'number')
            ang = window.orientation;
        HEAPF64[base + 6] = ang;
        return M.state();
    }, s_raw);
}

void request_enable() {
    install_watch();
    EM_ASM({
        window.__ollinMotion.enable();
    });
}

void forget_request() {
    EM_ASM({
        if (window.__ollinMotion)
            window.__ollinMotion.wanted = false;
    });
}
#else
bool s_wanted = false;

int sample_raw() {
    return s_wanted ? ST_UNSUPPORTED : ST_OFF;
}

void request_enable() {
    s_wanted = true;
}

void forget_request() {
    s_wanted = false;
}
#endif

// Rotates (x, y) by the screen's angle, counter-clockwise: a device turned that far counter-clockwise
// from its natural orientation has its screen axes at that angle to the device's.
void to_screen(double c, double s, double x, double y, double& out_x, double& out_y) {
    out_x = x * c - y * s;
    out_y = x * s + y * c;
}

void derive(Reading& r) {
    const double alpha = s_raw[0] * k_rad;
    const double beta = s_raw[1] * k_rad;
    const double gamma = s_raw[2] * k_rad;
    double angle = std::fmod(s_raw[6], 360.0);
    if (angle < 0.0)
        angle += 360.0;
    const double theta = angle * k_rad;
    const double c = std::cos(theta);
    const double s = std::sin(theta);

    // UP in the device frame, then in the screen frame (see the note at the top of the file).
    const double up_x = -std::cos(beta) * std::sin(gamma);
    const double up_y = std::sin(beta);
    const double up_z = std::cos(beta) * std::cos(gamma);
    double sx = 0.0;
    double sy = 0.0;
    to_screen(c, s, up_x, up_y, sx, sy);
    r.roll = std::asin(std::fmax(-1.0, std::fmin(1.0, -sx))) / k_rad;
    r.pitch = std::atan2(up_z, sy) / k_rad;
    r.gravity[0] = sx * k_gravity;
    r.gravity[1] = sy * k_gravity;
    r.gravity[2] = up_z * k_gravity;

    to_screen(c, s, s_raw[3], s_raw[4], r.acceleration[0], r.acceleration[1]);
    r.acceleration[2] = s_raw[5];

    // The attitude: the spec composes alpha (Z), beta (X') and gamma (Y'') into the rotation that
    // takes device vectors to the earth frame (x east, y north, z up). A rotation by the screen's
    // angle first makes it the SCREEN frame, and a quarter turn about X makes the earth frame the
    // 3D world's (x east, y up, z south). The screen frame — x right, y up, z towards the viewer —
    // is already a camera's: looking along -z.
    Quaternion q = QuaternionFromAxisAngle({1.0f, 0.0f, 0.0f}, (float)(-90.0 * k_rad));
    q = QuaternionMultiply(q, QuaternionFromAxisAngle({0.0f, 0.0f, 1.0f}, (float)alpha));
    q = QuaternionMultiply(q, QuaternionFromAxisAngle({1.0f, 0.0f, 0.0f}, (float)beta));
    q = QuaternionMultiply(q, QuaternionFromAxisAngle({0.0f, 1.0f, 0.0f}, (float)gamma));
    q = QuaternionMultiply(q, QuaternionFromAxisAngle({0.0f, 0.0f, 1.0f}, (float)-theta));
    r.attitude = QuaternionNormalize(q);
    r.has_attitude = true;
}

int motion_state(CallCtx& ctx) {
    return ctx.ret(Value(std::string(state_name(s_cur.state))));
}

int motion_enable(CallCtx& ctx) {
    request_enable();
    s_cur.state = sample_raw();
    return motion_state(ctx);
}

int motion_tilt(CallCtx& ctx) {
    ctx.set_result(0, Value(s_cur.roll));
    ctx.set_result(1, Value(s_cur.pitch));
    return 2;
}

int return_triple(CallCtx& ctx, const double* v) {
    ctx.set_result(0, Value(v[0]));
    ctx.set_result(1, Value(v[1]));
    ctx.set_result(2, Value(v[2]));
    return 3;
}

int motion_gravity(CallCtx& ctx) {
    return return_triple(ctx, s_cur.gravity);
}

int motion_acceleration(CallCtx& ctx) {
    return return_triple(ctx, s_cur.acceleration);
}

int motion_attitude(CallCtx& ctx) {
    if (!s_cur.has_attitude)
        return ctx.ret(Value{});
    return ctx.ret(make_quat_instance(s_cur.attitude));
}

} // namespace

void motion_begin_frame() {
#ifdef __EMSCRIPTEN__
    install_watch();
#endif
    Reading next;
    next.state = sample_raw();
    if (next.state == ST_ON)
        derive(next);
    s_cur = next;
}

void motion_reset() {
    forget_request();
    s_cur = Reading();
}

Value make_motion_module() {
    return MapBuilder()
        .fn("enable", motion_enable)
        .fn("state", motion_state)
        .fn("tilt", motion_tilt)
        .fn("gravity", motion_gravity)
        .fn("acceleration", motion_acceleration)
        .fn("attitude", motion_attitude)
        .done();
}
