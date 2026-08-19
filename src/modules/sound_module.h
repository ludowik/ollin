#pragma once
#include "value.h"
#include <stdexcept>
#include <string>

// Module `sound` : ce qui SONNE. Deux natures d'objet, deux mécaniques :
//   un OSCILLATEUR vivant, dont on déplace la fréquence pendant qu'il sonne ;
//   un TAMPON figé (calculé ou chargé), qu'on déclenche — à venir.
//
// Règle qui gouverne tout le module : AUCUN code Ollin ne tourne dans le rappel audio.
// Celui-ci a une échéance de quelques millisecondes — la manquer s'entend comme un clic —
// et appeler la VM depuis là signifierait exécuter du bytecode et allouer sous cette
// contrainte. La forme d'onde est donc calculée en C++, le script ne réglant que des
// nombres ; et une formule écrite en Ollin sera échantillonnée UNE fois, hors du rappel.
Value make_sound_module();

// Remise à zéro au démarrage d'un programme (ollin_run), comme ui_reset : les statiques
// survivent au VM entre deux exécutions du playground, et un oscillateur du programme
// précédent continuerait de sonner.
void sound_reset();

// Une fois par frame : ouvre le flux de sortie dès que le périphérique est prêt (au
// navigateur, cela n'arrive qu'après le premier geste de l'utilisateur).
void sound_update();

// ── Formes d'onde ───────────────────────────────────────────────────────────────
// Les noms exposés vivent dans des littéraux de chaîne, donc en camelCase comme le reste
// de l'API. `noise` n'a pas de fréquence, mais l'accepte sans s'en servir : refuser
// obligerait l'appelant à connaître ce cas particulier.
enum SoundShape { SHAPE_SINE = 0, SHAPE_SQUARE, SHAPE_SAW, SHAPE_TRIANGLE, SHAPE_NOISE };

inline const char* sound_shape_names() {
    return "sine, square, saw, triangle, noise";
}

inline const char* sound_shape_name(int shape) {
    static const char* k_names[] = {"sine", "square", "saw", "triangle", "noise"};
    return (shape >= 0 && shape < 5) ? k_names[shape] : k_names[0];
}

inline int sound_shape_index(const std::string& name, const char* fn) {
    for (int i = 0; i < 5; i++) {
        if (name == sound_shape_name(i))
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": forme d'onde inconnue '" + name + "' — disponibles : " +
                             sound_shape_names());
}

// ── Validation, PARTAGÉE par le module et le stub ────────────────────────────────
// Une faute d'appel doit être signalée même sans périphérique : c'est le stub qui tourne
// dans le conteneur d'intégration, donc dans les tests.

// Fréquence audible utile. La borne haute n'est pas un caprice : au-delà de la moitié de
// la fréquence d'échantillonnage, une onde se replie et descend au lieu de monter.
inline double sound_check_freq(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return -1.0;   // absente : l'appelant garde sa valeur courante
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": la fréquence doit être un nombre de hertz");
    double hz = args[i].as_num();
    if (hz < 0.0 || hz > 20000.0)
        throw std::runtime_error(std::string(fn) + ": fréquence hors de [0;20000] hertz");
    return hz;
}

inline int sound_check_shape(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return SHAPE_SINE;
    if (!args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": la forme d'onde doit être un nom — " + sound_shape_names());
    return sound_shape_index(args[i].as_string(), fn);
}

// Enveloppe : quatre nombres, dont trois durées en secondes et un niveau de maintien dans
// [0;1]. Une durée négative est refusée — c'est une faute de frappe, pas une intention.
inline void sound_check_envelope(const Value* args, int argc, const char* fn) {
    if (argc < 4)
        throw std::runtime_error(std::string(fn) + ": attendu attaque, déclin, maintien, relâchement");
    for (int i = 0; i < 4; i++) {
        if (!args[i].is_number())
            throw std::runtime_error(std::string(fn) + ": les quatre valeurs doivent être des nombres");
        if (args[i].as_num() < 0.0)
            throw std::runtime_error(std::string(fn) + ": aucune valeur ne peut être négative");
    }
    if (args[2].as_num() > 1.0)
        throw std::runtime_error(std::string(fn) + ": le maintien est un niveau, entre 0 et 1");
}

inline double sound_check_hold(const Value* args, int argc, const char* fn) {
    if (argc < 1 || args[0].is_nil())
        return -1.0;   // note TENUE : elle sonnera jusqu'à release()
    if (!args[0].is_number())
        throw std::runtime_error(std::string(fn) + ": la durée doit être un nombre de secondes");
    if (args[0].as_num() <= 0.0)
        throw std::runtime_error(std::string(fn) + ": la durée doit être > 0");
    return args[0].as_num();
}

// Volume et panoramique : bornés en silence, comme le volume général. Un panoramique de
// -1 est à gauche, 0 au centre, 1 à droite (convention de raylib et de p5).
inline double sound_check_unit(const Value* args, int argc, int i, const char* fn, const char* quoi, double mini) {
    if (i >= argc || args[i].is_nil())
        return -2.0;   // absent : l'appelant garde sa valeur courante
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": " + quoi + " doit être un nombre");
    double v = args[i].as_num();
    return v < mini ? mini : (v > 1.0 ? 1.0 : v);
}
