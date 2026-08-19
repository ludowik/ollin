#pragma once
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
    std::atomic<float> freq{440.0f};
    std::atomic<float> volume{0.5f};
    std::atomic<float> pan{0.0f};
    // Privés au fil audio.
    double phase = 0.0;
    float gain = 0.0f;
    uint32_t noise_state = 0x9e3779b9u;
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
