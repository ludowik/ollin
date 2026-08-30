#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"
#include "raylib.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif

// Sound session, build WITH raylib. The device is NOT opened when the module loads: the browser
// refuses to sound before an interaction, and opening too early would give a suspended context
// with nothing useful to do about it. Opening is therefore deferred until the user's first gesture
// (audio_wake), or an explicit call to audio.start().

namespace {

bool s_ready = false;
bool s_tried = false;     // an attempt already happened; do not retry it every frame
double s_volume = 1.0;

#ifdef __EMSCRIPTEN__
// A SUSPENDED audio context can only be resumed from the gesture handler itself. That is Safari's
// rule on iOS, and it dooms our wake-up: audio_wake starts from the render loop, hence outside the
// gesture's call stack, and its resume is refused — for good. The sound was then dead until the tab
// was closed (MEASURED: with the context suspended by force, three further gestures brought no
// sound back).
//
// Safari suspends of its own accord on an interruption (an incoming call, coming back from the
// background, locking), and a context created before any gesture is born suspended. Hence a DOM
// listener, installed ONCE and kept: every gesture retries the resume, which covers both cases
// without the engine having to know which one occurred.
void install_gesture_resume() {
    static bool installed = false;
    if (installed)
        return;
    installed = true;
    EM_ASM({
        if (window.__ollinAudioResume)
            return;
        window.__ollinAudioResume = 1;
        var resume = function() {
            var ma = window.miniaudio;
            if (!ma || !ma.devices)
                return;
            for (var i = 0; i < ma.devices.length; i++) {
                var d = ma.devices[i];
                if (d && d.webaudio && d.webaudio.state !== 'running' && d.webaudio.resume)
                    d.webaudio.resume();
            }
        };
        // No array or object literal here: EM_ASM is a MACRO, and a comma outside parentheses
        // separates its arguments.
        var opt = { capture: true };
        opt.passive = true;
        var names = 'pointerdown touchstart touchend mousedown keydown'.split(' ');
        for (var i = 0; i < names.length; i++)
            document.addEventListener(names[i], resume, opt);
    });
}
#else
void install_gesture_resume() {
}
#endif

// Opens the device once. A failure is not a script error: a machine with no sound card (the
// integration container, a server) must run the program through to the end, in silence.
bool audio_open() {
    if (s_ready)
        return true;
    if (s_tried)
        return false;
    s_tried = true;
    InitAudioDevice();
    s_ready = IsAudioDeviceReady();
    if (s_ready)
        SetMasterVolume((float)s_volume);
    return s_ready;
}

int audio_start(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(audio_open()));
}

int audio_is_ready(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(s_ready));
}

// With no argument it returns the current volume; with one it sets it and returns it, to chain.
int audio_volume(CallCtx& ctx) {
    audio_check_volume_args(ctx.args, ctx.argc);
    if (ctx.argc >= 1 && ctx.args[0].is_number()) {
        s_volume = audio_clamp_volume(ctx.args[0].as_num());
        if (s_ready)
            SetMasterVolume((float)s_volume);
    }
    return ctx.ret(Value(s_volume));
}

int audio_sample_rate(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)k_audio_sample_rate));
}

// Pause belongs to the SESSION rather than to each sound: it is the audio counterpart of pausing a
// render loop. It suspends progress, where a zero volume would let everything run on in silence and
// the sound would resume further along than where it was left.
int audio_pause(CallCtx& ctx) {
    sound_set_paused(true);
    return ctx.ret(Value{});
}

int audio_resume(CallCtx& ctx) {
    sound_set_paused(false);
    return ctx.ret(Value{});
}

int audio_is_paused(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(sound_paused()));
}

} // namespace

void audio_wake() {
    audio_open();
}

void audio_update() {
}

// The device itself is NOT closed: it belongs to the page on WASM, and closing it would invalidate
// buffers still referenced. Only the program's own state is reset — the volume, which a previous
// script may have turned down.
void audio_reset() {
    // The resume listener must be in place BEFORE the first gesture, hence when the program starts
    // rather than when the device opens — that happens only after a gesture, which would already be
    // lost.
    install_gesture_resume();
    s_volume = 1.0;
    if (s_ready)
        SetMasterVolume(1.0f);
}

Value make_audio_module() {
    return MapBuilder()
        .fn("start", audio_start)
        .fn("isReady", audio_is_ready)
        .fn("volume", audio_volume)
        .fn("pause", audio_pause)
        .fn("resume", audio_resume)
        .fn("isPaused", audio_is_paused)
        .fn("sampleRate", audio_sample_rate)
        .done();
}
