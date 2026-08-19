#pragma once
#include "sound_env.h"
#include <atomic>
#include <cstdint>

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

enum { SOUND_SHAPE_COUNT = 5 };

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
