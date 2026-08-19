#include "sound_internal.h"

// Sortie sonore, build SANS raylib : il n'y a pas de périphérique, donc rien à ouvrir et
// rien à mélanger. Tout le reste du module `sound` fonctionne — les voix existent, leurs
// paramètres se lisent et s'écrivent, la validation refuse les mêmes appels. C'est ce qui
// rend les oscillateurs testables dans un conteneur sans carte son.

void sound_output_ensure() {
}

void sound_output_silence() {
}
