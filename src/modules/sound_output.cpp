#include "sound_internal.h"
#include "audio_module.h"
#include "raylib.h"
#include <atomic>
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
std::atomic<uint64_t> s_mix_epoch{0};

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

// Mélange les TAMPONS déclenchés. Les échantillons ne sont lus que tant que `playing` est
// vrai — invariant sur lequel repose la sûreté mémoire, le fil principal ne réutilisant un
// slot qu'après l'avoir tu ET attendu un bloc.
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
        double avance = b.rate.load(std::memory_order_relaxed);
        bool boucle = b.loop.load(std::memory_order_relaxed);
        float g_gauche = pan > 0.0f ? 1.0f - pan : 1.0f;
        float g_droite = pan < 0.0f ? 1.0f + pan : 1.0f;
        for (unsigned int i = 0; i < frames; i++) {
            if (b.pos >= (double)n) {
                if (!boucle) {
                    b.playing.store(false, std::memory_order_relaxed);
                    break;
                }
                // Le reste du dépassement est conservé : le retrancher ferait perdre une
                // fraction d'échantillon à chaque tour, donc dériver une boucle rythmique.
                b.pos -= (double)n;
            }
            // Interpolation linéaire entre deux échantillons : à vitesse 1 elle rend la
            // valeur exacte, et une hauteur modifiée ne s'entend pas crénelée.
            size_t i0 = (size_t)b.pos;
            size_t i1 = (i0 + 1 < n) ? i0 + 1 : (boucle ? 0 : i0);
            float f = (float)(b.pos - (double)i0);
            float s = (data[i0] * (1.0f - f) + data[i1] * f) * volume;
            out[i * 2] += s * g_gauche;
            out[i * 2 + 1] += s * g_droite;
            b.pos += avance;
        }
    }
}

void mix_callback(void* buffer, unsigned int frames) {
    float* out = (float*)buffer;
    for (unsigned int i = 0; i < frames * 2; i++)
        out[i] = 0.0f;
    // En pause : du silence, et RIEN n'avance — ni les phases, ni les positions de lecture,
    // ni les enveloppes. Le son reprend donc là où il s'est arrêté.
    if (sound_paused()) {
        s_mix_epoch.fetch_add(1, std::memory_order_release);
        return;
    }
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
        float volume = (float)v.volume.load(std::memory_order_relaxed);
        float cible = actif ? volume : 0.0f;
        int shape = v.shape.load(std::memory_order_relaxed);
        double avance = v.freq.load(std::memory_order_relaxed) * pas_temps;
        float pan = (float)v.pan.load(std::memory_order_relaxed);
        // Enveloppe : lue une fois par bloc. La faire varier au sein d'un bloc n'apporterait
        // rien — 23 ms séparent deux blocs, soit moins qu'une frame.
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
            // Lâcher demandé par le script : l'instant est figé ici, car le relâchement part
            // du niveau atteint À CE MOMENT et non du niveau de maintien.
            //
            // Le PLUS TÔT des deux gagne : une note déclenchée avec une durée a déjà son
            // instant de lâcher, et ne tester que « pas encore lâchée » rendait release()
            // sans effet dans ce cas — trigger(2.0) suivi d'un release() au bout de 0,2 s
            // laissait sonner les deux secondes entières.
            if (!v.gate.load(std::memory_order_relaxed) && (v.env_hold_at < 0.0 || v.env_t < v.env_hold_at))
                v.env_hold_at = v.env_t;
        }
        // Panoramique sans creux au centre : chaque côté reste à plein volume tant qu'on
        // n'a pas dépassé le milieu.
        float g_gauche = pan > 0.0f ? 1.0f - pan : 1.0f;
        float g_droite = pan < 0.0f ? 1.0f + pan : 1.0f;
        for (unsigned int i = 0; i < frames; i++) {
            if (env_used && actif) {
                cible = volume * (float)adsr_level(env, v.env_t, v.env_hold_at);
                v.env_t += pas_temps;
            }
            // Le lissage s'applique PAR-DESSUS l'enveloppe : une attaque nulle serait sinon
            // un saut, donc un clic. Cinq millisecondes ne s'entendent pas comme un fondu.
            v.gain += (cible - v.gain) * lissage;
            float s = wave_sample(shape, v.phase, v.noise_state) * v.gain;
            out[i * 2] += s * g_gauche;
            out[i * 2 + 1] += s * g_droite;
            v.phase += avance;
            if (v.phase >= 1.0)
                v.phase -= 1.0;
        }
        // Une note relâchée cesse d'occuper la voix : sans cela un programme qui déclenche
        // des notes épuiserait la table, chaque voix restant marquée « en train de sonner ».
        if (env_used && actif && adsr_finished(env, v.env_t, v.env_hold_at))
            v.active.store(false, std::memory_order_relaxed);
        if (!actif && v.gain < 0.0001f)
            v.gain = 0.0f;
    }
    mix_buffers(out, frames);
    // Compté EN DERNIER : le fil principal en déduit qu'un bloc complet s'est écoulé, donc
    // qu'aucune lecture de ce bloc ne traîne plus.
    s_mix_epoch.fetch_add(1, std::memory_order_release);
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
    // Compensation de la loi de panoramique de raylib, qui ne vaut PAS 1 au centre : son
    // mélangeur applique `volume * 0.5 * c * (3 - c²)` par canal, soit 0,6875 pour un flux
    // centré (c = 0,5). Sans ce correctif, un volume demandé à 1 sortait à 0,687 — mesuré au
    // navigateur, analyseur branché sur la sortie, avant d'être retrouvé dans raudio.c.
    SetAudioStreamVolume(s_stream, 1.0f / 0.6875f);
    SetAudioStreamCallback(s_stream, mix_callback);
    PlayAudioStream(s_stream);
    s_stream_ready = true;
}

// Le flux n'est PAS déchargé : il appartient au périphérique, qui survit au programme (au
// playground, la page reste chargée). Les voix étant déjà éteintes par sound_reset, le
// mélangeur rend du silence — il n'y a rien de plus à faire.
void sound_output_silence() {
}

uint64_t sound_mix_epoch() {
    return s_mix_epoch.load(std::memory_order_acquire);
}
