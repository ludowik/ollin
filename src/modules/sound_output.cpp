#include "sound_internal.h"
#include "audio_module.h"
#include "raylib.h"
#include <cmath>

// Sortie sonore, build AVEC raylib : UN SEUL flux pour toutes les voix, mélangé ici.
//
// Un flux par voix serait impossible sans duplication : le rappel de raylib ne transporte
// aucune donnée utilisateur (sa signature n'a que le tampon et le nombre de trames), donc
// il faudrait autant de fonctions distinctes que de voix. Un mélangeur unique est aussi
// l'endroit naturel où viendront la pause globale et les tampons déclenchés.
//
// TOUT ce fichier, sous le rappel, s'exécute sur le fil audio (natif) ou dans le rappel
// Web Audio (navigateur), sous une échéance de quelques millisecondes : aucune allocation,
// aucun verrou, aucun appel à la VM. Les paramètres réglés par le script sont lus
// atomiquement, un par un.

namespace {

// Lissage du gain, en secondes. Démarrer ou arrêter une onde carrée d'un coup produit un
// clic très audible : le gain rejoint sa cible en quelques millisecondes — trop vite pour
// s'entendre comme un fondu, assez lentement pour supprimer la discontinuité.
constexpr double k_gain_ramp = 0.005;

AudioStream s_stream{};
bool s_stream_ready = false;

// Bruit propre à la voix : xorshift, quelques opérations entières. `rand()` serait
// interdit ici — état global partagé, et rien ne garantit qu'il soit sans verrou.
inline float noise_next(uint32_t& state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return (float)((double)state / 2147483648.0 - 1.0);
}

inline float wave_sample(int shape, double phase, uint32_t& noise_state) {
    switch (shape) {
    case 1:   // square
        return phase < 0.5 ? 1.0f : -1.0f;
    case 2:   // saw
        return (float)(2.0 * phase - 1.0);
    case 3:   // triangle
        return (float)(1.0 - 4.0 * std::fabs(phase - 0.5));
    case 4:   // noise
        return noise_next(noise_state);
    default:  // sine
        return (float)std::sin(phase * 6.283185307179586);
    }
}

void mix_callback(void* buffer, unsigned int frames) {
    float* out = (float*)buffer;
    for (unsigned int i = 0; i < frames * 2; i++)
        out[i] = 0.0f;
    const double pas_temps = 1.0 / (double)k_audio_sample_rate;
    const float lissage = (float)(pas_temps / k_gain_ramp);
    Voice* voices = sound_voices();
    for (int k = 0; k < k_max_voices; k++) {
        Voice& v = voices[k];
        bool actif = v.active.load(std::memory_order_relaxed);
        // Une voix arrêtée reste mélangée le temps que son gain retombe à zéro, sinon
        // l'arrêt claque.
        if (!actif && v.gain <= 0.0f)
            continue;
        float cible = actif ? v.volume.load(std::memory_order_relaxed) : 0.0f;
        int shape = v.shape.load(std::memory_order_relaxed);
        double avance = (double)v.freq.load(std::memory_order_relaxed) * pas_temps;
        float pan = v.pan.load(std::memory_order_relaxed);
        // Panoramique sans creux au centre : chaque côté reste à plein volume tant qu'on
        // n'a pas dépassé le milieu.
        float g_gauche = pan > 0.0f ? 1.0f - pan : 1.0f;
        float g_droite = pan < 0.0f ? 1.0f + pan : 1.0f;
        for (unsigned int i = 0; i < frames; i++) {
            v.gain += (cible - v.gain) * lissage;
            float s = wave_sample(shape, v.phase, v.noise_state) * v.gain;
            out[i * 2] += s * g_gauche;
            out[i * 2 + 1] += s * g_droite;
            v.phase += avance;
            if (v.phase >= 1.0)
                v.phase -= 1.0;
        }
        if (!actif && v.gain < 0.0001f)
            v.gain = 0.0f;
    }
}

} // namespace

void sound_output_ensure() {
    if (s_stream_ready || !IsAudioDeviceReady())
        return;
    // ~23 ms à 44,1 kHz : assez court pour que le son suive le clic, assez long pour
    // survivre à une frame chargée. Au navigateur le mélange partage le fil de la VM
    // (le dos-end passe par un ScriptProcessorNode), donc un tampon plus petit
    // craquerait au premier calcul un peu lourd.
    SetAudioStreamBufferSizeDefault(1024);
    s_stream = LoadAudioStream(k_audio_sample_rate, 32, 2);
    SetAudioStreamCallback(s_stream, mix_callback);
    PlayAudioStream(s_stream);
    s_stream_ready = true;
}

// Le flux n'est PAS déchargé : il appartient au périphérique, qui survit au programme (au
// playground, la page reste chargée). Les voix étant déjà éteintes par sound_reset, le
// mélangeur rend du silence — il n'y a rien de plus à faire.
void sound_output_silence() {
}
