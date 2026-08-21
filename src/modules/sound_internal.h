#pragma once
#include "sound_env.h"
#include <atomic>
#include <cstdint>
#include <vector>

// Boundary between the `sound` module's API and its OUTPUT.
//
// The voice state and all the API logic live in sound_module.cpp, which is compiled in EVERY
// build: that is what makes oscillators testable without a device, in the integration container
// that has none. Only the output changes — sound_output.cpp with raylib (a stream and a mixer),
// sound_output_stub.cpp without (nothing at all).
//
// The mixer reads this table from the AUDIO THREAD while the script writes it, so every parameter
// is atomic and the table has a FIXED size: a growing vector would move the voices out from under
// the mixer.

constexpr int k_max_voices = 16;

struct Voice {
    // Written by the script, read by the audio thread.
    std::atomic<bool> active{false};
    std::atomic<int> shape{0};
    // DOUBLE, not float: a script must read back exactly what it wrote, and 0.01 stored as a
    // float comes back as 0.009999999776, which no longer equals itself. Verified lock-free on
    // both targets (native x86-64 and wasm), as the audio thread requires.
    std::atomic<double> freq{440.0};
    std::atomic<double> volume{0.5};
    std::atomic<double> pan{0.0};
    // The envelope is OPT-IN: without it the volume applies as is, and an oscillator with no
    // envelope behaves exactly as it did before envelopes existed.
    std::atomic<bool> env_used{false};
    std::atomic<double> env_attack{0.01};
    std::atomic<double> env_decay{0.05};
    std::atomic<double> env_sustain{0.7};
    std::atomic<double> env_release{0.2};
    // Time before the automatic release, as passed to trigger(duration); a negative value means
    // the note is held until release().
    std::atomic<double> env_hold{-1.0};
    // A COUNTER, not a flag: re-triggering a note that is still sounding must restart from the
    // attack, which a boolean already set to true could not express.
    std::atomic<uint32_t> trigger_id{0};
    std::atomic<bool> gate{false};
    // Private to the audio thread.
    double phase = 0.0;
    float gain = 0.0f;
    uint32_t noise_state = 0x9e3779b9u;
    uint32_t seen_trigger = 0;
    double env_t = 0.0;        // time elapsed since the trigger
    double env_hold_at = -1.0; // moment of release, -1 while the note is held
    // Private to the main thread: the script-side handle identity.
    uint32_t gen = 1;
    bool used = false;
    uint64_t born = 0;   // creation rank, so the OLDEST voice is recycled first
};

Voice* sound_voices();

// Opens the output stream when the device is ready, and does nothing otherwise: a voice started
// too early simply waits — it is already active and will sound as soon as the stream exists.
// Called every frame and when an oscillator starts.
void sound_output_ensure();

// Silences the output without tearing it down: the device and the stream outlive the program,
// since in the playground the page stays loaded.
void sound_output_silence();

// Is a mix actually running? Only then does a released voice keep sounding on its own, and only
// then is its slot worth protecting: with no output (a headless build, or the browser before the
// first gesture opens the device) nothing ever finishes an envelope, so a slot given back by
// free() would never come back into use.
bool sound_output_running();

// Buffers: a COMPUTED (or loaded) sound, triggered on demand.
// The samples are written once, by the main thread, then only READ by the mixer — and only while
// `playing` is true. That invariant is what makes the memory safe without a lock: reusing a slot
// therefore means silencing it first, then waiting for one mix block to elapse (see mix_epoch
// below), because a block already under way may have read `playing` before we cleared it.

constexpr int k_max_buffers = 32;

// Maximum length of a buffer. Generating one second of audio takes 44,100 calls into the script's
// function, so this bound keeps a typo — a duration in milliseconds taken for seconds — from
// freezing the engine for minutes.
constexpr double k_max_buffer_seconds = 10.0;

struct Buf {
    std::vector<float> samples;   // mono ; le panoramique est appliqué à la lecture
    std::atomic<bool> playing{false};
    std::atomic<bool> loop{false};
    std::atomic<double> volume{0.5};
    std::atomic<double> pan{0.0};
    std::atomic<double> rate{1.0};
    // Private to the audio thread.
    double pos = 0.0;
    // Private to the main thread.
    uint32_t gen = 1;
    bool used = false;
    uint64_t retired_epoch = 0;   // bloc de mélange où le slot a été rendu
};

Buf* sound_buffers();

// GLOBAL pause: the mixer returns silence and advances neither the phases nor the read positions.
// That is what sets it apart from a zero volume, where everything would keep running and resuming
// would find the sound further along than where it was left.
bool sound_paused();
void sound_set_paused(bool paused);

// How many mix blocks have been produced. It is the single synchronization point between the main
// thread and the audio thread for reusing a buffer slot.
uint64_t sound_mix_epoch();
