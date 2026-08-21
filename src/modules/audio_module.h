#pragma once
#include "value.h"
#include <stdexcept>

// The `audio` module: the sound SESSION — opening the device, master volume, state. One per
// program, like the graphics canvas.
//
// Unlike `graphics`, this module is NEVER nil: a build without raylib keeps the whole API and only
// the output goes silent (audio_stub.cpp). The reason is that generating waveforms is pure
// computation, and therefore testable without a device — and the integration container has none,
// `/dev/snd` being absent.
Value make_audio_module();

// The engine calls these three itself, from its render loop and when a program starts. They are
// not meant for scripts: forgetting one would be an engine defect, not a user mistake.
//
// audio_wake()   on the user's first gesture (a click, a key). The browser refuses to sound before
//                an interaction, so opening the device at load time would achieve nothing; the
//                engine does it at that moment and the script has nothing to write.
// audio_update() once per frame after opening (restarting loops, upkeep).
// audio_reset()  when a PROGRAM starts (ollin_run), like ui_reset: the statics survive the VM
//                between two playground runs.
void audio_wake();
void audio_update();
void audio_reset();

// Output sample rate, and the unit of every synthesis computation. A constant rather than a
// setting: changing it would invalidate the buffers already computed.
constexpr int k_audio_sample_rate = 44100;

// Argument validation, SHARED by the module and the stub.
// A misuse must be reported even with no device — the test binary has none — so the messages live
// in a single place and cannot diverge.
inline void audio_check_volume_args(const Value* args, int argc) {
    if (argc >= 1 && !args[0].is_nil() && !args[0].is_number())
        throw std::runtime_error("audio.volume: expected a number between 0 and 1");
}

// The volume is clamped to [0;1]: beyond that the output saturates and the sound distorts instead
// of getting louder. We correct silently rather than refuse, as with colour components.
inline double audio_clamp_volume(double v) {
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}
