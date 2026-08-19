#pragma once

// Enveloppe ADSR — attaque, déclin, maintien, relâchement.
//
// Écrite en FORME FERMÉE (le niveau à l'instant t) et non en machine à états, pour une
// raison de vérifiabilité : la même fonction sert au mélangeur, qui la parcourt en temps
// réel sur le fil audio, et au calcul d'un tampon, qui l'applique hors ligne. Un test qui
// lit les échantillons d'un tampon valide donc la formule que le mélangeur emploie — or le
// conteneur d'intégration n'a pas de carte son, et n'a aucun autre moyen de la contrôler.
//
// Les durées sont en secondes, `sustain` est un niveau dans [0;1].

struct Adsr {
    double attack = 0.01;
    double decay = 0.05;
    double sustain = 0.7;
    double release = 0.2;
};

// Niveau au temps `t` compté depuis le déclenchement. `hold` est l'instant où le
// relâchement commence — la durée passée à `trigger(durée)`, ou l'instant où le script a
// appelé `release()`. Négatif : la note est encore tenue, donc le maintien se prolonge.
inline double adsr_level(const Adsr& e, double t, double hold) {
    if (t <= 0.0)
        return 0.0;
    if (hold >= 0.0 && t >= hold) {
        // Le relâchement part du niveau atteint AU MOMENT du lâcher, pas du maintien :
        // lâcher pendant l'attaque doit redescendre depuis là où l'on était.
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

// L'enveloppe est-elle retombée à zéro ? Sert au mélangeur pour libérer la voix : une note
// relâchée doit cesser d'occuper un slot.
inline bool adsr_finished(const Adsr& e, double t, double hold) {
    return hold >= 0.0 && t >= hold + e.release;
}
