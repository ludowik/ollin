#pragma once
#include "sound_env.h"
#include <atomic>
#include <cstdint>
#include <vector>

// Frontière entre l'API du module `sound` et sa SORTIE.
//
// L'état des voix et toute la logique d'API vivent dans sound_module.cpp, compilé dans
// TOUS les builds : c'est ce qui permet de tester les oscillateurs sans périphérique, dans
// le conteneur d'intégration qui n'en a aucun. Seule la sortie change — sound_output.cpp
// avec raylib (un flux et un mélangeur), sound_output_stub.cpp sans (rien du tout).
//
// Le mélangeur lit cette table depuis le FIL AUDIO pendant que le script l'écrit : chaque
// paramètre est donc atomique, et la table est de taille FIXE — un vecteur qui grandirait
// déplacerait les voix sous les pieds du mélangeur.

constexpr int k_max_voices = 16;

struct Voice {
    // Écrits par le script, lus par le fil audio.
    std::atomic<bool> active{false};
    std::atomic<int> shape{0};
    // En DOUBLE, et non en float : un script doit relire exactement ce qu'il a écrit, or
    // 0,01 rangé en float remonte à 0,009999999776 et ne s'égale plus à lui-même. Vérifié
    // sans verrou sur les deux cibles (natif x86-64 et wasm), ce qu'exige le fil audio.
    std::atomic<double> freq{440.0};
    std::atomic<double> volume{0.5};
    std::atomic<double> pan{0.0};
    // Enveloppe, OPT-IN : sans elle le volume s'applique tel quel, et le comportement d'un
    // oscillateur sans enveloppe est exactement celui d'avant son introduction.
    std::atomic<bool> env_used{false};
    std::atomic<double> env_attack{0.01};
    std::atomic<double> env_decay{0.05};
    std::atomic<double> env_sustain{0.7};
    std::atomic<double> env_release{0.2};
    // Durée avant relâchement automatique, passée à trigger(durée) ; négative = note tenue
    // jusqu'à release().
    std::atomic<double> env_hold{-1.0};
    // Un COMPTEUR, pas un drapeau : re-déclencher une note qui sonne encore doit repartir de
    // l'attaque, ce qu'un booléen déjà vrai ne saurait pas dire.
    std::atomic<uint32_t> trigger_id{0};
    std::atomic<bool> gate{false};
    // Privés au fil audio.
    double phase = 0.0;
    float gain = 0.0f;
    uint32_t noise_state = 0x9e3779b9u;
    uint32_t seen_trigger = 0;
    double env_t = 0.0;        // temps écoulé depuis le déclenchement
    double env_hold_at = -1.0; // instant du lâcher, -1 tant que la note est tenue
    // Privés au fil principal : identité du handle côté script.
    uint32_t gen = 1;
    bool used = false;
    uint64_t born = 0;   // rang de création, pour recycler la voix la plus ANCIENNE
};

Voice* sound_voices();

// Ouvre le flux de sortie si le périphérique est prêt, sinon ne fait rien — une voix
// démarrée trop tôt attend simplement : elle est déjà active et sonnera dès que le flux
// existera. Appelé à chaque frame et au démarrage d'un oscillateur.
void sound_output_ensure();

// Fait taire la sortie sans la démonter : le périphérique et le flux survivent au
// programme (au playground, la page reste chargée).
void sound_output_silence();

// ── Tampons : un son CALCULÉ (ou chargé), qu'on déclenche ────────────────────────
// Les échantillons sont écrits une fois, par le fil principal, puis seulement LUS par le
// mélangeur — et uniquement tant que `playing` est vrai. C'est cet invariant qui rend la
// mémoire sûre sans verrou : réutiliser un slot exige donc de le taire d'abord, puis
// d'attendre qu'un bloc de mélange se soit écoulé (cf. mix_epoch ci-dessous), car un bloc
// déjà en cours peut avoir lu `playing` avant qu'on l'éteigne.

constexpr int k_max_buffers = 32;

// Durée maximale d'un tampon. Générer une seconde d'audio demande 44 100 appels à la
// fonction du script : la borne empêche qu'une faute de frappe (une durée en millisecondes
// prise pour des secondes) fige le moteur pendant des minutes.
constexpr double k_max_buffer_seconds = 10.0;

struct Buf {
    std::vector<float> samples;   // mono ; le panoramique est appliqué à la lecture
    std::atomic<bool> playing{false};
    std::atomic<bool> loop{false};
    std::atomic<double> volume{0.5};
    std::atomic<double> pan{0.0};
    std::atomic<double> rate{1.0};
    // Privés au fil audio.
    double pos = 0.0;
    // Privés au fil principal.
    uint32_t gen = 1;
    bool used = false;
    uint64_t retired_epoch = 0;   // bloc de mélange où le slot a été rendu
};

Buf* sound_buffers();

// Pause GLOBALE : le mélangeur rend du silence et n'avance ni les phases ni les positions
// de lecture. C'est ce qui la distingue d'un volume à zéro, où tout continuerait de courir
// et où reprendre ferait retrouver le son plus loin qu'on l'a laissé.
bool sound_paused();
void sound_set_paused(bool paused);

// Nombre de blocs de mélange déjà produits. Sert d'unique point de synchronisation entre le
// fil principal et le fil audio pour la réutilisation d'un slot de tampon.
uint64_t sound_mix_epoch();
