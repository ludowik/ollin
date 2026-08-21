#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"

// Session sonore, build SANS raylib : aucune sortie, donc aucun son audible. Le module
// still exists in full — unlike `graphics`, which is nil — because generating waveforms is pure
// computation: it runs identically here, and that is what makes synthesis testable in a container
// with no sound card.
//
// The volume is kept so that reading audio.volume() returns what the script wrote: an accessor
// that forgot its value would fail a test for the wrong reason.

namespace {

double s_volume = 1.0;

int stub_start(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(false));
}

int stub_is_ready(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(false));
}

int stub_volume(CallCtx& ctx) {
    audio_check_volume_args(ctx.args, ctx.argc);
    if (ctx.argc >= 1 && ctx.args[0].is_number())
        s_volume = audio_clamp_volume(ctx.args[0].as_num());
    return ctx.ret(Value(s_volume));
}

int stub_sample_rate(CallCtx& ctx) {
    return ctx.ret(Value((int64_t)k_audio_sample_rate));
}

// Pause belongs to the SESSION rather than to each sound: it is the audio counterpart of pausing
// a render loop. It suspends progress, where a zero volume would let everything run on in silence
// and the sound would resume further along than where it was left.
int stub_pause(CallCtx& ctx) {
    sound_set_paused(true);
    return ctx.ret(Value{});
}

int stub_resume(CallCtx& ctx) {
    sound_set_paused(false);
    return ctx.ret(Value{});
}

int stub_is_paused(CallCtx& ctx) {
    return ctx.ret(Value::make_bool(sound_paused()));
}

} // namespace

void audio_wake() {
}

void audio_update() {
}

void audio_reset() {
    s_volume = 1.0;
}

Value make_audio_module() {
    Value m = Value::make_map();
    m.map_set(Value(std::string("start")), Value::make_builtin(stub_start));
    m.map_set(Value(std::string("isReady")), Value::make_builtin(stub_is_ready));
    m.map_set(Value(std::string("volume")), Value::make_builtin(stub_volume));
    m.map_set(Value(std::string("pause")), Value::make_builtin(stub_pause));
    m.map_set(Value(std::string("resume")), Value::make_builtin(stub_resume));
    m.map_set(Value(std::string("isPaused")), Value::make_builtin(stub_is_paused));
    m.map_set(Value(std::string("sampleRate")), Value::make_builtin(stub_sample_rate));
    return m;
}
