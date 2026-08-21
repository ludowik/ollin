#include "sound_internal.h"
#include <cstdint>

// Sound output, build WITHOUT raylib: there is no device, so nothing to open and nothing to mix.
// All the rest of the `sound` module works — voices exist, their parameters can be read and
// written, validation refuses the same calls. That is what
// makes oscillators testable in a container with no sound card.

void sound_output_ensure() {
}

void sound_output_silence() {
}

// With no output nobody reads the samples, so the epoch advances on every call, which makes a
// buffer slot immediately reusable.
uint64_t sound_mix_epoch() {
    static uint64_t epoque = 0;
    return ++epoque;
}
