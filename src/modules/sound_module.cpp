#include "sound_module.h"
#include "audio_module.h"
#include "module_utils.h"
#include "sound_internal.h"
#include <atomic>
#include <cmath>
#include <string>
#include <vector>

// The `sound` module: its API and state, in EVERY build. The output, by contrast, depends on
// raylib (sound_output.cpp / sound_output_stub.cpp) — see sound_internal.h.
//
// An oscillator is a VOICE in a fixed table. The script only ever handles a {slot, gen} handle and
// never a pointer: `gen` detects a stale handle instead of silently addressing whichever voice
// recycled the slot.

namespace {

Voice* voices() {
    return sound_voices();
}

Value osc_class();

Value make_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), osc_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)voices()[slot].gen));
    return h;
}

int handle_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected an oscillator");
    int i = (int)slot.as_int();
    if (i < 0 || i >= k_max_voices || voices()[i].gen != (uint32_t)gen.as_int())
        throw std::runtime_error(std::string(fn) + ": this oscillator no longer exists");
    return i;
}

// A free slot, otherwise the OLDEST STOPPED voice. Without this recycling a program creating
// oscillators on demand would exhaust the table, and a voice that is still sounding is never
// stolen.
//
// The creation rank decides, rather than the first slot that comes: "the first stopped one" kept
// hammering voice 0 and never touched the others, so one oscillator could survive twenty creations
// while its neighbour did not survive a single one (observed).
uint64_t s_born_counter = 0;

// A voice only sounds if something renders it. Without an output, an envelope is never finished,
// so a slot given back by free() would stay protected for ever and the sixteenth creation would
// fail with "no oscillator available" (measured with the headless binary).
bool voice_sounding(const Voice& v) {
    if (!sound_output_running())
        return false;
    return v.active.load(std::memory_order_relaxed) || v.gain > 0.0f;
}

int alloc_voice() {
    Voice* v = voices();
    for (int i = 0; i < k_max_voices; i++) {
        // Returned by `free` but not yet silent: the slot is free, the SOUND is not. Taking it back
        // would cut off the note tail the script has just released.
        if (!v[i].used && !voice_sounding(v[i]))
            return i;
    }
    int chosen = -1;
    for (int i = 0; i < k_max_voices; i++) {
        if (voice_sounding(v[i]))
            continue;
        if (chosen < 0 || v[i].born < v[chosen].born)
            chosen = i;
    }
    if (chosen >= 0) {
        v[chosen].gen++;
        return chosen;
    }
    throw std::runtime_error("sound: no oscillator available (" + std::to_string(k_max_voices) +
                             " at a time, all still sounding)");
}

int make_osc(const Value* args, int argc, const char* fn, int shape_forced) {
    double hz = sound_check_freq(args, argc, 0, fn);
    int shape = shape_forced >= 0 ? shape_forced : sound_check_shape(args, argc, 1, fn);
    int slot = alloc_voice();
    Voice& v = voices()[slot];
    v.used = true;
    v.born = ++s_born_counter;
    v.active.store(false, std::memory_order_relaxed);
    v.shape.store(shape, std::memory_order_relaxed);
    v.freq.store(hz < 0.0 ? 440.0 : hz, std::memory_order_relaxed);
    v.volume.store(0.5, std::memory_order_relaxed);
    v.pan.store(0.0, std::memory_order_relaxed);
    v.gain = 0.0f;
    v.phase = 0.0;
    v.env_used.store(false, std::memory_order_relaxed);
    v.gate.store(false, std::memory_order_relaxed);
    v.env_hold.store(-1.0, std::memory_order_relaxed);
    return slot;
}

// The conversion is exposed as such: a script building a scale needs the number, not only an
// oscillator.
int sound_note(CallCtx& ctx) {
    if (ctx.argc < 1 || !ctx.args[0].is_string())
        throw std::runtime_error("sound.note: expected a note name, like \"C#4\"");
    return ctx.ret(Value(sound_note_hz(ctx.args[0].as_string(), "sound.note")));
}

int sound_osc(CallCtx& ctx) {
    return ctx.ret(make_handle(make_osc(ctx.args, ctx.argc, "sound.osc", -1)));
}

// Per-waveform shortcuts, as in p5: more readable than a name passed as a string, and a misspelled
// name becomes impossible.
template <int SHAPE>
int sound_shape_factory(CallCtx& ctx) {
    static const char* k_fn[] = {"sound.sine", "sound.square", "sound.saw", "sound.triangle", "sound.noise"};
    return ctx.ret(make_handle(make_osc(ctx.args, ctx.argc, k_fn[SHAPE], SHAPE)));
}

int method_start(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.start");
    audio_wake();   // starting a sound implicitly asks for the device
    sound_output_ensure();
    voices()[i].active.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_stop(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.stop");
    voices()[i].active.store(false, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_is_playing(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.isPlaying");
    return ctx.ret(Value::make_bool(voices()[i].active.load(std::memory_order_relaxed)));
}

// The accessors follow the graphics.font rule: with no argument they READ, with one they write and
// return the handle, which makes them chainable.
int method_freq(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.freq");
    double hz = sound_check_freq(ctx.args + 1, ctx.argc - 1, 0, "sound.freq");
    if (hz < 0.0)
        return ctx.ret(Value(voices()[i].freq.load(std::memory_order_relaxed)));
    voices()[i].freq.store(hz, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_volume(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.volume");
    double v = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.volume", "volume", 0.0);
    if (v < -1.0)
        return ctx.ret(Value(voices()[i].volume.load(std::memory_order_relaxed)));
    voices()[i].volume.store(v, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_pan(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.pan");
    double p = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.pan", "pan", -1.0);
    if (p < -1.5)
        return ctx.ret(Value(voices()[i].pan.load(std::memory_order_relaxed)));
    voices()[i].pan.store(p, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_shape(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.shape");
    if (ctx.argc < 2 || ctx.args[1].is_nil())
        return ctx.ret(Value(std::string(sound_shape_name(voices()[i].shape.load(std::memory_order_relaxed)))));
    voices()[i].shape.store(sound_check_shape(ctx.args + 1, ctx.argc - 1, 0, "sound.shape"),
                            std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// The envelope belongs to the oscillator rather than to a separate object as in p5: there it can
// modulate any Web Audio parameter, here it has a single target — a voice's volume. A second kind of
// handle would therefore add nothing worth remembering.
int method_envelope(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.envelope");
    Voice& v = voices()[i];
    if (ctx.argc < 2) {
        Value m = Value::make_map();
        m.map_set(Value(std::string("attack")), Value(v.env_attack.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("decay")), Value(v.env_decay.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("sustain")), Value(v.env_sustain.load(std::memory_order_relaxed)));
        m.map_set(Value(std::string("release")), Value(v.env_release.load(std::memory_order_relaxed)));
        return ctx.ret(m);
    }
    sound_check_envelope(ctx.args + 1, ctx.argc - 1, "sound.envelope");
    v.env_attack.store(ctx.args[1].as_num(), std::memory_order_relaxed);
    v.env_decay.store(ctx.args[2].as_num(), std::memory_order_relaxed);
    v.env_sustain.store(ctx.args[3].as_num(), std::memory_order_relaxed);
    v.env_release.store(ctx.args[4].as_num(), std::memory_order_relaxed);
    v.env_used.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// trigger([duration]) plays the note. Without a duration it is HELD until release(); with one, the
// release starts by itself at the deadline, which is enough for a beep or a melody note.
int method_trigger(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.trigger");
    double hold = sound_check_hold(ctx.args + 1, ctx.argc - 1, "sound.trigger");
    Voice& v = voices()[i];
    v.env_used.store(true, std::memory_order_relaxed);
    v.env_hold.store(hold, std::memory_order_relaxed);
    v.gate.store(true, std::memory_order_relaxed);
    // The counter is incremented LAST: it is what the mixer watches to restart from the attack, and
    // it must find the other parameters already set.
    v.trigger_id.fetch_add(1, std::memory_order_relaxed);
    audio_wake();
    sound_output_ensure();
    v.active.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int method_release(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.release");
    voices()[i].gate.store(false, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// free() means "I no longer need this". Without it a script could NOT create its oscillators on
// demand: alloc_voice takes back the oldest stopped voice, so any handle still held risked
// addressing a recycled slot — the error is reported, but the program is broken. Hence the
// pre-allocated pool every polyphonic script had to write.
//
// The note is NOT cut: the envelope is released as `release` would, and the slot is only handed back
// once silent — alloc_voice already refuses a voice whose gain has not fallen. Cutting abruptly
// would click, and would lose the note tail the script has just released.
int method_free(CallCtx& ctx) {
    int i = handle_slot(ctx.args[0], "sound.free");
    Voice& v = voices()[i];
    v.gate.store(false, std::memory_order_relaxed);
    if (!v.env_used.load(std::memory_order_relaxed))
        v.active.store(false, std::memory_order_relaxed);   // with no envelope, nothing to fade out
    v.used = false;
    v.gen++;   // the handle goes stale: reusing it is reported, not silently ignored
    return ctx.ret(Value{});
}


// Buffers: a COMPUTED sound, triggered on demand.
// Same pattern as the voices: a fixed table and a {slot, gen} handle. What differs is the lifetime
// of the SAMPLES, which the mixer reads from another thread — hence the reuse protocol described in
// sound_internal.h.

Buf* bufs() {
    return sound_buffers();
}

Value buffer_class();

Value make_buffer_handle(int slot) {
    Value h = Value::make_map();
    h.map_set(Value(std::string("__class__")), buffer_class());
    h.map_set(Value(std::string("slot")), Value((int64_t)slot));
    h.map_set(Value(std::string("gen")), Value((int64_t)bufs()[slot].gen));
    return h;
}

int buffer_slot(const Value& self, const char* fn) {
    Value slot = self.map_get(Value(std::string("slot")));
    Value gen = self.map_get(Value(std::string("gen")));
    if (!slot.is_integer() || !gen.is_integer())
        throw std::runtime_error(std::string(fn) + ": expected a sound");
    int i = (int)slot.as_int();
    if (i < 0 || i >= k_max_buffers || bufs()[i].gen != (uint32_t)gen.as_int())
        throw std::runtime_error(std::string(fn) + ": this sound no longer exists");
    return i;
}

// A free slot, otherwise the one returned longest ago — provided a mix block has elapsed since.
// Without that wait, a block already under way could read the samples while they are replaced.
int alloc_buffer() {
    Buf* b = bufs();
    for (int i = 0; i < k_max_buffers; i++) {
        if (!b[i].used)
            return i;
    }
    uint64_t now = sound_mix_epoch();
    int chosen = -1;
    for (int i = 0; i < k_max_buffers; i++) {
        if (b[i].playing.load(std::memory_order_relaxed))
            continue;
        if (b[i].retired_epoch >= now)
            continue;   // given back too recently: a block may still be reading it
        if (chosen < 0 || b[i].retired_epoch < b[chosen].retired_epoch)
            chosen = i;
    }
    if (chosen < 0)
        throw std::runtime_error("sound: no sound slot available (" + std::to_string(k_max_buffers) +
                                 " at a time)");
    b[chosen].gen++;
    return chosen;
}

int new_buffer(std::vector<float>&& samples) {
    int slot = alloc_buffer();
    Buf& b = bufs()[slot];
    b.used = true;
    b.samples = std::move(samples);
    b.playing.store(false, std::memory_order_relaxed);
    b.loop.store(false, std::memory_order_relaxed);
    b.volume.store(0.5, std::memory_order_relaxed);
    b.pan.store(0.0, std::memory_order_relaxed);
    b.rate.store(1.0, std::memory_order_relaxed);
    b.pos = 0.0;
    return slot;
}

// Waveform sampled offline. It is the SAME shape table as the oscillator's, but computed here once
// and for all, so a buffer costs nothing to play.
double wave_at(int shape, double phase, uint32_t& noise_state) {
    switch (shape) {
    case SHAPE_SQUARE:
        return phase < 0.5 ? 1.0 : -1.0;
    case SHAPE_SAW:
        return 2.0 * phase - 1.0;
    case SHAPE_TRIANGLE:
        return 1.0 - 4.0 * std::fabs(phase - 0.5);
    case SHAPE_NOISE:
        noise_state ^= noise_state << 13;
        noise_state ^= noise_state >> 17;
        noise_state ^= noise_state << 5;
        return (double)noise_state / 2147483648.0 - 1.0;
    default:
        return std::sin(phase * 6.283185307179586);
    }
}

int sound_tone(CallCtx& ctx) {
    const char* FN = "sound.tone";
    double hz = sound_check_freq(ctx.args, ctx.argc, 0, FN);
    if (hz < 0.0)
        throw std::runtime_error(std::string(FN) + ": expected a frequency as first argument");
    double duration = sound_check_duration(ctx.args, ctx.argc, 1, FN);
    int shape = sound_check_shape(ctx.args, ctx.argc, 2, FN);
    size_t n = (size_t)(duration * k_audio_sample_rate);
    std::vector<float> samples(n);
    double phase = 0.0;
    double step = hz / (double)k_audio_sample_rate;
    uint32_t noise_state = 0x9e3779b9u;
    for (size_t i = 0; i < n; i++) {
        samples[i] = (float)wave_at(shape, phase, noise_state);
        phase += step;
        if (phase >= 1.0)
            phase -= 1.0;
    }
    return ctx.ret(make_buffer_handle(new_buffer(std::move(samples))));
}

// The script's formula is sampled ONCE, here, on the main thread: it never enters the audio
// callback, where running bytecode under a hard deadline would be heard as a crackle.
int sound_generate(CallCtx& ctx) {
    const char* FN = "sound.generate";
    double duration = sound_check_duration(ctx.args, ctx.argc, 0, FN);
    if (ctx.argc < 2 || !ctx.args[1].is_callable())
        throw std::runtime_error(std::string(FN) + ": expected a second argument: a function of time");
    Value f = ctx.args[1];
    size_t n = (size_t)(duration * k_audio_sample_rate);
    std::vector<float> samples(n);
    VM* vm = VM::current();
    double pas = 1.0 / (double)k_audio_sample_rate;
    for (size_t i = 0; i < n; i++) {
        Value r = vm->call_value(f, Value((double)i * pas));
        // A non-numeric value counts as zero: throwing on the 30,000th sample would give an
        // incomprehensible message, and the formula is usually right everywhere else.
        double v = r.is_number() ? r.as_num() : 0.0;
        samples[i] = (float)(v < -1.0 ? -1.0 : (v > 1.0 ? 1.0 : v));
    }
    return ctx.ret(make_buffer_handle(new_buffer(std::move(samples))));
}

int buf_play(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.play");
    audio_wake();
    sound_output_ensure();
    Buf& b = bufs()[i];
    b.pos = 0.0;   // replaying starts from the beginning, as PlaySound does
    b.playing.store(true, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_stop(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.stop");
    bufs()[i].playing.store(false, std::memory_order_relaxed);
    bufs()[i].retired_epoch = sound_mix_epoch();
    return ctx.ret(ctx.args[0]);
}

int buf_is_playing(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.isPlaying");
    return ctx.ret(Value::make_bool(bufs()[i].playing.load(std::memory_order_relaxed)));
}

int buf_volume(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.volume");
    double v = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.volume", "volume", 0.0);
    if (v < -1.0)
        return ctx.ret(Value(bufs()[i].volume.load(std::memory_order_relaxed)));
    bufs()[i].volume.store(v, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_pan(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.pan");
    double p = sound_check_unit(ctx.args + 1, ctx.argc - 1, 0, "sound.pan", "pan", -1.0);
    if (p < -1.5)
        return ctx.ret(Value(bufs()[i].pan.load(std::memory_order_relaxed)));
    bufs()[i].pan.store(p, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// `rate` changes the playback speed, hence both the pitch AND the length, like speeding up a
// record. It is p5's name, and it makes clear this is not a transposition.
int buf_rate(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.rate");
    if (ctx.argc < 2 || ctx.args[1].is_nil())
        return ctx.ret(Value(bufs()[i].rate.load(std::memory_order_relaxed)));
    if (!ctx.args[1].is_number())
        throw std::runtime_error("sound.rate: rate must be a number");
    double r = ctx.args[1].as_num();
    if (r <= 0.0 || r > 16.0)
        throw std::runtime_error("sound.rate: rate out of ]0;16]");
    bufs()[i].rate.store(r, std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

int buf_loop(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.loop");
    if (ctx.argc < 2 || ctx.args[1].is_nil()) {
        bufs()[i].loop.store(true, std::memory_order_relaxed);
        return ctx.ret(ctx.args[0]);
    }
    if (!ctx.args[1].is_bool())
        throw std::runtime_error("sound.loop: expected true, false, or no argument");
    bufs()[i].loop.store(ctx.args[1].as_bool(), std::memory_order_relaxed);
    return ctx.ret(ctx.args[0]);
}

// Accessors: what makes synthesis VERIFIABLE.
// Without them the only thing a test could check would be the refusals: the integration container
// has no sound card, and nobody is listening.

int buf_duration(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.duration");
    return ctx.ret(Value((double)bufs()[i].samples.size() / (double)k_audio_sample_rate));
}

int buf_peak(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.peak");
    double crete = 0.0;
    for (float s : bufs()[i].samples) {
        double a = s < 0.0f ? -(double)s : (double)s;
        if (a > crete)
            crete = a;
    }
    return ctx.ret(Value(crete));
}

// Sample at time t, in seconds. Outside the buffer it returns zero, like the surrounding silence,
// rather than an error: a test sweeping over time readily overshoots the end by a few
// microseconds.
int buf_sample(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.sample");
    if (ctx.argc < 2 || !ctx.args[1].is_number())
        throw std::runtime_error("sound.sample: expected a time in seconds");
    double t = ctx.args[1].as_num();
    const std::vector<float>& d = bufs()[i].samples;
    if (t < 0.0)
        return ctx.ret(Value(0.0));
    size_t idx = (size_t)(t * k_audio_sample_rate);
    if (idx >= d.size())
        return ctx.ret(Value(0.0));
    return ctx.ret(Value((double)d[idx]));
}

// The envelope is applied TO THE SAMPLES, once: a buffer has no held note, so the release ends
// exactly at the end of the sound. It is the same function the mixer uses (sound_env.h), so a test
// on a buffer validates the curve for both.
int buf_envelope(CallCtx& ctx) {
    int i = buffer_slot(ctx.args[0], "sound.envelope");
    sound_check_envelope(ctx.args + 1, ctx.argc - 1, "sound.envelope");
    Adsr e;
    e.attack = ctx.args[1].as_num();
    e.decay = ctx.args[2].as_num();
    e.sustain = ctx.args[3].as_num();
    e.release = ctx.args[4].as_num();
    std::vector<float>& d = bufs()[i].samples;
    double duration = (double)d.size() / (double)k_audio_sample_rate;
    double hold = duration - e.release;
    if (hold < 0.0)
        hold = 0.0;
    for (size_t k = 0; k < d.size(); k++) {
        double t = (double)k / (double)k_audio_sample_rate;
        d[k] = (float)((double)d[k] * adsr_level(e, t, hold));
    }
    return ctx.ret(ctx.args[0]);
}

Value make_buffer_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Sound")
        .fn("play", buf_play)
        .fn("stop", buf_stop)
        .fn("isPlaying", buf_is_playing)
        .fn("volume", buf_volume)
        .fn("pan", buf_pan)
        .fn("rate", buf_rate)
        .fn("loop", buf_loop)
        .fn("duration", buf_duration)
        .fn("peak", buf_peak)
        .fn("sample", buf_sample)
        .fn("envelope", buf_envelope)
        .done();
}

Value buffer_class() {
    static Value cls = make_buffer_class();
    return cls;
}

Value make_osc_class() {
    return MapBuilder(Value::make_class())
        .str("__name__", "Osc")
        .fn("start", method_start)
        .fn("stop", method_stop)
        .fn("isPlaying", method_is_playing)
        .fn("freq", method_freq)
        .fn("volume", method_volume)
        .fn("pan", method_pan)
        .fn("shape", method_shape)
        .fn("envelope", method_envelope)
        .fn("trigger", method_trigger)
        .fn("release", method_release)
        .fn("free", method_free)
        .done();
}

Value osc_class() {
    static Value cls = make_osc_class();
    return cls;
}

} // namespace

// The voice table lives HERE, in the file compiled everywhere: the output reaches it only through
// sound_voices(), so the mixer needs to know nothing about the module.
Voice* sound_voices() {
    static Voice table[k_max_voices];
    return table;
}

// Pause flag: read by the mixer on every block, written by the session (the audio module).
std::atomic<bool>& paused_flag() {
    static std::atomic<bool> paused{false};
    return paused;
}

bool sound_paused() {
    return paused_flag().load(std::memory_order_relaxed);
}

void sound_set_paused(bool paused) {
    paused_flag().store(paused, std::memory_order_relaxed);
}

Buf* sound_buffers() {
    static Buf table[k_max_buffers];
    return table;
}

void sound_reset() {
    sound_set_paused(false);
    // The buffers are SILENCED but their samples are not freed: a mix block already under way may
    // still read them, and there is no hurry — the slot will be reused later, once a block has
    // elapsed (see alloc_buffer).
    Buf* b = sound_buffers();
    for (int i = 0; i < k_max_buffers; i++) {
        b[i].playing.store(false, std::memory_order_relaxed);
        b[i].used = false;
        b[i].gen++;
        b[i].retired_epoch = sound_mix_epoch();
    }
    Voice* v = sound_voices();
    for (int i = 0; i < k_max_voices; i++) {
        v[i].active.store(false, std::memory_order_relaxed);
        v[i].used = false;
        v[i].gen++;
    }
    sound_output_silence();
}

void sound_update() {
    sound_output_ensure();
}

Value make_sound_module() {
    return MapBuilder()
        .fn("osc", sound_osc)
        .set("sine", Value::make_builtin(sound_shape_factory<SHAPE_SINE>))
        .set("square", Value::make_builtin(sound_shape_factory<SHAPE_SQUARE>))
        .set("saw", Value::make_builtin(sound_shape_factory<SHAPE_SAW>))
        .set("triangle", Value::make_builtin(sound_shape_factory<SHAPE_TRIANGLE>))
        .set("noise", Value::make_builtin(sound_shape_factory<SHAPE_NOISE>))
        .fn("note", sound_note)
        .fn("tone", sound_tone)
        .fn("generate", sound_generate)
        .done();
}
