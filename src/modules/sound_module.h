#pragma once
#include "sound_internal.h"
#include "value.h"
#include <cmath>
#include <stdexcept>
#include <string>

// The `sound` module: what SOUNDS. Two kinds of object, two mechanics:
//   a live OSCILLATOR, whose frequency can be moved while it sounds;
//   a frozen BUFFER (computed or loaded), which is triggered.
//
// The rule that governs the whole module: NO Ollin code runs in the audio callback. That callback
// has a deadline of a few milliseconds — missing it is heard as a click — and calling the VM from
// there would mean running bytecode and allocating under that constraint. The waveform is therefore
// computed in C++, with the script only setting numbers, and a formula written in Ollin is sampled
// ONCE, outside the callback.
Value make_sound_module();

// Reset when a program starts (ollin_run), like ui_reset: the statics survive the VM between two
// playground runs, and an oscillator from the previous program would keep sounding.
void sound_reset();

// Once per frame: opens the output stream as soon as the device is ready — in a browser, only
// after the user's first gesture.
void sound_update();

// The exposed names live in string literals, hence camelCase like the rest of the API. `noise` has
// no frequency but accepts one and ignores it: refusing would force the caller to know about that
// special case.
enum SoundShape { SHAPE_SINE = 0, SHAPE_SQUARE, SHAPE_SAW, SHAPE_TRIANGLE, SHAPE_NOISE, SHAPE_COUNT };

inline const char* sound_shape_names() {
    return "sine, square, saw, triangle, noise";
}

inline const char* sound_shape_name(int shape) {
    static const char* k_names[] = {"sine", "square", "saw", "triangle", "noise"};
    return (shape >= 0 && shape < SHAPE_COUNT) ? k_names[shape] : k_names[0];
}

inline int sound_shape_index(const std::string& name, const char* fn) {
    for (int i = 0; i < SHAPE_COUNT; i++) {
        if (name == sound_shape_name(i))
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": unknown waveform '" + name + "' — available: " +
                             sound_shape_names());
}

// Validation, SHARED by the module and the stub.
// A misuse must be reported even without a device: the stub is what runs in the integration
// container, and therefore in the tests.

// Note name to hertz: "A4" is 440, then "C#5", "Eb3", and "C-1" for the lowest octave. Equal
// temperament does the arithmetic, so there is no frequency table to copy.
inline double sound_note_hz(const std::string& name, const char* fn) {
    static const int k_semitones[] = {9, 11, 0, 2, 4, 5, 7};   // A B C D E F G
    if (name.empty())
        throw std::runtime_error(std::string(fn) + ": empty note name");
    char letter = name[0];
    if (letter >= 'a' && letter <= 'g')
        letter = (char)(letter - 'a' + 'A');
    if (letter < 'A' || letter > 'G')
        throw std::runtime_error(std::string(fn) + ": unknown note '" + name + "' — expected A to G, like \"C#4\"");
    int semitone = k_semitones[letter - 'A'];
    size_t k = 1;
    if (k < name.size() && (name[k] == '#' || name[k] == 'b')) {
        semitone += (name[k] == '#') ? 1 : -1;
        k++;
    }
    if (k >= name.size())
        throw std::runtime_error(std::string(fn) + ": note '" + name + "' has no octave — write for example \"A4\"");
    bool negative = name[k] == '-';
    if (negative)
        k++;
    if (k >= name.size())
        throw std::runtime_error(std::string(fn) + ": note '" + name + "' has no octave — write for example \"A4\"");
    int octave = 0;
    for (; k < name.size(); k++) {
        if (name[k] < '0' || name[k] > '9')
            throw std::runtime_error(std::string(fn) + ": note '" + name + "': unreadable octave");
        octave = octave * 10 + (name[k] - '0');
    }
    if (negative)
        octave = -octave;
    if (octave < -1 || octave > 9)
        throw std::runtime_error(std::string(fn) + ": octave out of [-1;9] in '" + name + "'");
    // MIDI number, then equal temperament around A 440.
    int midi = (octave + 1) * 12 + semitone;
    return 440.0 * std::pow(2.0, (midi - 69) / 12.0);
}

// Usable audible frequency. The upper bound is not arbitrary: past half the sample rate a wave
// folds back and goes down instead of up.
//
// A NOTE NAME is accepted everywhere a frequency is — here and nowhere else: this single gate
// covers sound.osc, sound.tone and osc.freq at once.
inline double sound_check_freq(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return -1.0;   // absente : l'appelant garde sa valeur courante
    if (args[i].is_string())
        return sound_note_hz(args[i].as_string(), fn);
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": frequency must be a number of hertz or a note name");
    double hz = args[i].as_num();
    if (hz < 0.0 || hz > 20000.0)
        throw std::runtime_error(std::string(fn) + ": frequency out of [0;20000] hertz");
    return hz;
}

inline int sound_check_shape(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return SHAPE_SINE;
    if (!args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": waveform must be a name — " + sound_shape_names());
    return sound_shape_index(args[i].as_string(), fn);
}

// Envelope: four numbers, three of them durations in seconds and one a sustain level in [0;1]. A
// negative duration is refused — it is a typo, not an intention.
inline void sound_check_envelope(const Value* args, int argc, const char* fn) {
    if (argc < 4)
        throw std::runtime_error(std::string(fn) + ": expected attack, decay, sustain, release");
    for (int i = 0; i < 4; i++) {
        if (!args[i].is_number())
            throw std::runtime_error(std::string(fn) + ": all four values must be numbers");
        if (args[i].as_num() < 0.0)
            throw std::runtime_error(std::string(fn) + ": no value may be negative");
    }
    if (args[2].as_num() > 1.0)
        throw std::runtime_error(std::string(fn) + ": sustain is a level, between 0 and 1");
}

inline double sound_check_hold(const Value* args, int argc, const char* fn) {
    if (argc < 1 || args[0].is_nil())
        return -1.0;   // a HELD note: it sounds until release()
    if (!args[0].is_number())
        throw std::runtime_error(std::string(fn) + ": duration must be a number of seconds");
    if (args[0].as_num() <= 0.0)
        throw std::runtime_error(std::string(fn) + ": duration must be > 0");
    return args[0].as_num();
}

// Length of a buffer, in seconds. The upper bound guards against a typo: generating ten seconds
// already takes 441,000 calls into the script's function, and a duration accidentally given in
// milliseconds would freeze the engine.
inline double sound_check_duration(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || !args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": duration must be a number of seconds");
    double d = args[i].as_num();
    if (d <= 0.0)
        throw std::runtime_error(std::string(fn) + ": duration must be > 0");
    if (d > k_max_buffer_seconds)
        throw std::runtime_error(std::string(fn) + ": duration exceeds " +
                                 std::to_string((int)k_max_buffer_seconds) + " seconds");
    return d;
}

// Volume and pan are clamped silently, like the master volume. A pan of -1 is left, 0 centre and
// 1 right, following raylib and p5.
inline double sound_check_unit(const Value* args, int argc, int i, const char* fn, const char* quoi, double mini) {
    if (i >= argc || args[i].is_nil())
        return -2.0;   // absent : l'appelant garde sa valeur courante
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": " + quoi + " must be a number");
    double v = args[i].as_num();
    return v < mini ? mini : (v > 1.0 ? 1.0 : v);
}
