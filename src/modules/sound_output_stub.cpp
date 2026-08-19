#include "sound_internal.h"
#include <cstdint>

// Sortie sonore, build SANS raylib : il n'y a pas de périphérique, donc rien à ouvrir et
// rien à mélanger. Tout le reste du module `sound` fonctionne — les voix existent, leurs
// paramètres se lisent et s'écrivent, la validation refuse les mêmes appels. C'est ce qui
// rend les oscillateurs testables dans un conteneur sans carte son.

void sound_output_ensure() {
}

void sound_output_silence() {
}

// Sans sortie, personne ne lit les échantillons : l'époque avance donc à chaque appel, ce
// qui rend un slot de tampon immédiatement réutilisable.
uint64_t sound_mix_epoch() {
    static uint64_t epoque = 0;
    return ++epoque;
}
