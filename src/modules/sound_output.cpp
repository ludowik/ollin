#include "sound_internal.h"
#include "audio_module.h"
#include "raylib.h"
#include <atomic>
#include <cmath>

// Sound output, build WITH raylib: ONE stream for every voice, mixed here.
//
// One stream per voice would be impossible without duplication: raylib's callback carries no user
// data — its signature has only the buffer and the frame count — so it would take as many distinct
// functions as voices. A single mixer is also the natural home for the global pause and for
// triggered buffers.
//
// EVERYTHING in this file below the callback runs on the audio thread (native) or inside the Web
// Audio callback (browser), under a deadline of a few milliseconds: no allocation, no lock, no call
// into the VM. The parameters set by the script are read atomically, one by one.

namespace {

// Gain ramp, in seconds. Starting or stopping a square wave abruptly produces a very audible
// click, so the gain reaches its target over a few milliseconds — too fast to be heard as a fade,
// slow enough to remove the discontinuity.
constexpr double k_gain_ramp = 0.005;

AudioStream s_stream{};
bool s_stream_ready = false;
std::atomic<uint64_t> s_mix_epoch{0};

// Per-voice noise: xorshift, a few integer operations. rand() would be forbidden here — shared
// global state, with no guarantee of being lock-free.
inline float noise_next(uint32_t& state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return (float)((double)state / 2147483648.0 - 1.0);
}

// Correction of a DISCONTINUITY (PolyBLEP). A sawtooth or a square computed directly jumps from
// one value to another between two samples, and that jump carries harmonics far above half the
// sample rate, which FOLD back down as inharmonic partials. Hence a metallic, out-of-tune sound,
// all the more noticeable as the pitch glides — the folded partials go down as the note goes up.
//
// The remedy: near the jump, subtract the polynomial that rounds it over the duration of one
// sample. `t` is the phase, in [0;1), and `dt` its advance per sample.
inline double poly_blep(double t, double dt) {
    if (t < dt) {
        t = t / dt - 1.0;
        return -t * t;
    }
    if (t > 1.0 - dt) {
        t = (t - 1.0) / dt + 1.0;
        return t * t;
    }
    return 0.0;
}

inline float wave_sample(int shape, double phase, double dt, uint32_t& noise_state) {
    switch (shape) {
    case 1: {   // square: two discontinuities per turn, at 0 and at 0.5
        double s = phase < 0.5 ? 1.0 : -1.0;
        s += poly_blep(phase, dt);
        double half = phase + 0.5;
        if (half >= 1.0)
            half -= 1.0;
        s -= poly_blep(half, dt);
        return (float)s;
    }
    case 2:   // saw: a single discontinuity, where 1 wraps to 0
        return (float)(2.0 * phase - 1.0 - poly_blep(phase, dt));
    case 3:
        // The triangle is left DIRECT: it has no jump, only two slope breaks, and its harmonics
        // fall off as 1/n² instead of 1/n, so its folding sits more than twenty decibels below that
        // of the two shapes above. Correcting it would take a second polynomial, on the slope, for
        // an inaudible gain.
        return (float)(1.0 - 4.0 * std::fabs(phase - 0.5));
    case 4:   // noise
        return noise_next(noise_state);
    default:  // sine
        return (float)std::sin(phase * 6.283185307179586);
    }
}

// Mixes the triggered BUFFERS. The samples are read only while `playing` is true — the invariant
// the memory safety rests on, since the main thread reuses a slot only after silencing it AND
// waiting for one block.
void mix_buffers(float* out, unsigned int frames) {
    Buf* bufs = sound_buffers();
    for (int k = 0; k < k_max_buffers; k++) {
        Buf& b = bufs[k];
        if (!b.playing.load(std::memory_order_relaxed))
            continue;
        const float* data = b.samples.data();
        size_t n = b.samples.size();
        if (n == 0) {
            b.playing.store(false, std::memory_order_relaxed);
            continue;
        }
        float volume = (float)b.volume.load(std::memory_order_relaxed);
        float pan = (float)b.pan.load(std::memory_order_relaxed);
        double step = b.rate.load(std::memory_order_relaxed);
        bool looping = b.loop.load(std::memory_order_relaxed);
        float g_left = pan > 0.0f ? 1.0f - pan : 1.0f;
        float g_right = pan < 0.0f ? 1.0f + pan : 1.0f;
        for (unsigned int i = 0; i < frames; i++) {
            if (b.pos >= (double)n) {
                if (!looping) {
                    b.playing.store(false, std::memory_order_relaxed);
                    break;
                }
                // The overshoot is kept: dropping it would lose a fraction of a sample every turn
                // and a rhythmic loop would drift.
                b.pos -= (double)n;
            }
            // Linear interpolation between two samples: at rate 1 it returns the exact value, and a
            // shifted pitch does not sound aliased.
            size_t i0 = (size_t)b.pos;
            size_t i1 = (i0 + 1 < n) ? i0 + 1 : (looping ? 0 : i0);
            float f = (float)(b.pos - (double)i0);
            float s = (data[i0] * (1.0f - f) + data[i1] * f) * volume;
            out[i * 2] += s * g_left;
            out[i * 2 + 1] += s * g_right;
            b.pos += step;
        }
    }
}

void mix_callback(void* buffer, unsigned int frames) {
    float* out = (float*)buffer;
    for (unsigned int i = 0; i < frames * 2; i++)
        out[i] = 0.0f;
    // While paused: silence, and NOTHING advances — neither the phases, nor the read positions, nor
    // the envelopes. The sound therefore resumes where it stopped.
    if (sound_paused()) {
        s_mix_epoch.fetch_add(1, std::memory_order_release);
        return;
    }
    const double dt_sample = 1.0 / (double)k_audio_sample_rate;
    const float ramp = (float)(dt_sample / k_gain_ramp);
    Voice* voices = sound_voices();
    for (int k = 0; k < k_max_voices; k++) {
        Voice& v = voices[k];
        bool is_active = v.active.load(std::memory_order_relaxed);
        // A stopped voice keeps being mixed until its gain reaches zero, otherwise stopping clicks.
        if (!is_active && v.gain <= 0.0f)
            continue;
        float volume = (float)v.volume.load(std::memory_order_relaxed);
        float target = is_active ? volume : 0.0f;
        int shape = v.shape.load(std::memory_order_relaxed);
        double step = v.freq.load(std::memory_order_relaxed) * dt_sample;
        float pan = (float)v.pan.load(std::memory_order_relaxed);
        // The envelope is read once per block. Varying it within a block would gain nothing: two
        // blocks are 23 ms apart, less than a frame.
        bool env_used = v.env_used.load(std::memory_order_relaxed);
        Adsr env;
        if (env_used) {
            env.attack = v.env_attack.load(std::memory_order_relaxed);
            env.decay = v.env_decay.load(std::memory_order_relaxed);
            env.sustain = v.env_sustain.load(std::memory_order_relaxed);
            env.release = v.env_release.load(std::memory_order_relaxed);
            uint32_t tid = v.trigger_id.load(std::memory_order_relaxed);
            if (tid != v.seen_trigger) {
                v.seen_trigger = tid;
                v.env_t = 0.0;
                double hold = v.env_hold.load(std::memory_order_relaxed);
                v.env_hold_at = hold >= 0.0 ? hold : -1.0;
            }
            // A release asked for by the script: the moment is frozen here, because the release
            // starts from the level reached AT THAT POINT and not from the sustain level.
            //
            // The EARLIER of the two wins: a note triggered with a duration already has its release
            // moment, and testing only for "not released yet" made release() a no-op in that case —
            // trigger(2.0) followed by release() after 0.2 s let the full two seconds sound.
            if (!v.gate.load(std::memory_order_relaxed) && (v.env_hold_at < 0.0 || v.env_t < v.env_hold_at))
                v.env_hold_at = v.env_t;
        }
        // Pan without a dip at the centre: each side stays at full volume until the middle is
        // passed.
        float g_left = pan > 0.0f ? 1.0f - pan : 1.0f;
        float g_right = pan < 0.0f ? 1.0f + pan : 1.0f;
        for (unsigned int i = 0; i < frames; i++) {
            if (env_used && is_active) {
                target = volume * (float)adsr_level(env, v.env_t, v.env_hold_at);
                v.env_t += dt_sample;
            }
            // The ramp applies ON TOP OF the envelope: a zero attack would otherwise be a jump, and
            // therefore a click. Five milliseconds are not heard as a fade.
            v.gain += (target - v.gain) * ramp;
            float s = wave_sample(shape, v.phase, step, v.noise_state) * v.gain;
            out[i * 2] += s * g_left;
            out[i * 2 + 1] += s * g_right;
            v.phase += step;
            if (v.phase >= 1.0)
                v.phase -= 1.0;
        }
        // A released note stops occupying its voice: without this, a program triggering notes would
        // exhaust the table, every voice staying marked as still sounding.
        if (env_used && is_active && adsr_finished(env, v.env_t, v.env_hold_at))
            v.active.store(false, std::memory_order_relaxed);
        if (!is_active && v.gain < 0.0001f)
            v.gain = 0.0f;
    }
    mix_buffers(out, frames);
    // Counted LAST: the main thread infers from it that a whole block has elapsed, so no read from
    // that block is still in flight.
    s_mix_epoch.fetch_add(1, std::memory_order_release);
}

} // namespace

void sound_output_ensure() {
    if (s_stream_ready || !IsAudioDeviceReady())
        return;
    // About 23 ms at 44.1 kHz: short enough for the sound to follow the click, long enough to
    // survive a heavy frame. In a browser the mixing shares the VM's thread — the backend goes
    // through a ScriptProcessorNode — so a smaller buffer would crackle on the first heavy
    // computation.
    SetAudioStreamBufferSizeDefault(1024);
    s_stream = LoadAudioStream(k_audio_sample_rate, 32, 2);
    // Compensates raylib's pan law, which is NOT unity at the centre: its mixer applies
    // volume * 0.5 * c * (3 - c²) per channel, that is 0.6875 for a centred stream (c = 0.5).
    // Without this correction a volume asked at 1 came out at 0.687 — measured in the browser with
    // an analyser on the output, then found again in raudio.c.
    SetAudioStreamVolume(s_stream, 1.0f / 0.6875f);
    SetAudioStreamCallback(s_stream, mix_callback);
    PlayAudioStream(s_stream);
    s_stream_ready = true;
}

// The stream is NOT unloaded: it belongs to the device, which outlives the program, the playground
// page staying loaded. The voices having already been silenced by sound_reset, the mixer returns
// silence and there is nothing more to do.
void sound_output_silence() {
}

uint64_t sound_mix_epoch() {
    return s_mix_epoch.load(std::memory_order_acquire);
}
