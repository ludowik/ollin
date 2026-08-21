#pragma once

// ADSR envelope: attack, decay, sustain, release.
//
// Written in CLOSED FORM — the level at time t — rather than as a state machine, for
// verifiability: the same function serves the mixer, which walks it in real time on the audio
// thread, and the buffer computation, which applies it offline. A test reading a buffer's samples
// therefore validates the very formula the mixer uses — and the integration container has no
// sound card, so it has no other way to check it.
//
// Durations are in seconds; `sustain` is a level in [0;1].

struct Adsr {
    double attack = 0.01;
    double decay = 0.05;
    double sustain = 0.7;
    double release = 0.2;
};

// Level at time `t`, counted from the trigger. `hold` is when the release begins — the duration
// passed to trigger(duration), or the moment the script called release(). A negative value means
// the note is still held, so the sustain goes on.
inline double adsr_level(const Adsr& e, double t, double hold) {
    if (t <= 0.0)
        return 0.0;
    if (hold >= 0.0 && t >= hold) {
        // The release starts from the level reached AT the moment of letting go, not from the
        // sustain: releasing during the attack must come down from wherever we were.
        double depart = adsr_level(e, hold, -1.0);
        if (e.release <= 0.0)
            return 0.0;
        double u = (t - hold) / e.release;
        return u >= 1.0 ? 0.0 : depart * (1.0 - u);
    }
    if (t < e.attack)
        return e.attack <= 0.0 ? 1.0 : t / e.attack;
    double td = t - e.attack;
    if (td < e.decay)
        return e.decay <= 0.0 ? e.sustain : 1.0 - (1.0 - e.sustain) * (td / e.decay);
    return e.sustain;
}

// Has the envelope fallen back to zero? The mixer uses this to free the voice: a released note
// must stop occupying a slot.
inline bool adsr_finished(const Adsr& e, double t, double hold) {
    return hold >= 0.0 && t >= hold + e.release;
}
