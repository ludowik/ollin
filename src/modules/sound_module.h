#pragma once
#include "sound_internal.h"
#include "value.h"
#include <cmath>
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
enum SoundShape { SHAPE_SINE = 0, SHAPE_SQUARE, SHAPE_SAW, SHAPE_TRIANGLE, SHAPE_NOISE, SHAPE_COUNT };

inline const char* sound_shape_names() {
    return "sine, square, saw, triangle, noise";
}

inline const char* sound_shape_name(int shape) {
    static const char* k_names[] = {"sine", "square", "saw", "triangle", "noise"};
    return (shape >= 0 && shape < SHAPE_COUNT) ? k_names[shape] : k_names[0];
}

inline int sound_shape_index(const std::string& name, const char* fn) {
    for (int i = 0; i < SHAPE_COUNT; i++) {
        if (name == sound_shape_name(i))
            return i;
    }
    throw std::runtime_error(std::string(fn) + ": unknown waveform '" + name + "' — available: " +
                             sound_shape_names());
}

// ── Validation, PARTAGÉE par le module et le stub ────────────────────────────────
// Une faute d'appel doit être signalée même sans périphérique : c'est le stub qui tourne
// dans le conteneur d'intégration, donc dans les tests.

// Nom de note anglo-saxon vers hertz : "A4" = 440, "C#5", "Eb3", "C-1" pour l'octave la plus
// grave. Le tempérament égal fait le calcul, aucune table de fréquences à recopier.
inline double sound_note_hz(const std::string& name, const char* fn) {
    static const int k_demi_tons[] = {9, 11, 0, 2, 4, 5, 7};   // A B C D E F G
    if (name.empty())
        throw std::runtime_error(std::string(fn) + ": empty note name");
    char lettre = name[0];
    if (lettre >= 'a' && lettre <= 'g')
        lettre = (char)(lettre - 'a' + 'A');
    if (lettre < 'A' || lettre > 'G')
        throw std::runtime_error(std::string(fn) + ": unknown note '" + name + "' — expected A to G, like \"C#4\"");
    int demi = k_demi_tons[lettre - 'A'];
    size_t k = 1;
    if (k < name.size() && (name[k] == '#' || name[k] == 'b')) {
        demi += (name[k] == '#') ? 1 : -1;
        k++;
    }
    if (k >= name.size())
        throw std::runtime_error(std::string(fn) + ": note '" + name + "' has no octave — write for example \"A4\"");
    bool negatif = name[k] == '-';
    if (negatif)
        k++;
    if (k >= name.size())
        throw std::runtime_error(std::string(fn) + ": note '" + name + "' has no octave — write for example \"A4\"");
    int octave = 0;
    for (; k < name.size(); k++) {
        if (name[k] < '0' || name[k] > '9')
            throw std::runtime_error(std::string(fn) + ": note '" + name + "': unreadable octave");
        octave = octave * 10 + (name[k] - '0');
    }
    if (negatif)
        octave = -octave;
    if (octave < -1 || octave > 9)
        throw std::runtime_error(std::string(fn) + ": octave out of [-1;9] in '" + name + "'");
    // Numéro MIDI, puis tempérament égal autour du la 440.
    int midi = (octave + 1) * 12 + demi;
    return 440.0 * std::pow(2.0, (midi - 69) / 12.0);
}

// Fréquence audible utile. La borne haute n'est pas un caprice : au-delà de la moitié de
// la fréquence d'échantillonnage, une onde se replie et descend au lieu de monter.
//
// Un NOM DE NOTE est accepté partout où une fréquence l'est — ici et nulle part ailleurs :
// ce point de passage unique couvre sound.osc, sound.tone et osc.freq d'un seul coup.
inline double sound_check_freq(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return -1.0;   // absente : l'appelant garde sa valeur courante
    if (args[i].is_string())
        return sound_note_hz(args[i].as_string(), fn);
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": frequency must be a number of hertz or a note name");
    double hz = args[i].as_num();
    if (hz < 0.0 || hz > 20000.0)
        throw std::runtime_error(std::string(fn) + ": frequency out of [0;20000] hertz");
    return hz;
}

inline int sound_check_shape(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || args[i].is_nil())
        return SHAPE_SINE;
    if (!args[i].is_string())
        throw std::runtime_error(std::string(fn) + ": waveform must be a name — " + sound_shape_names());
    return sound_shape_index(args[i].as_string(), fn);
}

// Enveloppe : quatre nombres, dont trois durées en secondes et un niveau de maintien dans
// [0;1]. Une durée négative est refusée — c'est une faute de frappe, pas une intention.
inline void sound_check_envelope(const Value* args, int argc, const char* fn) {
    if (argc < 4)
        throw std::runtime_error(std::string(fn) + ": expected attack, decay, sustain, release");
    for (int i = 0; i < 4; i++) {
        if (!args[i].is_number())
            throw std::runtime_error(std::string(fn) + ": all four values must be numbers");
        if (args[i].as_num() < 0.0)
            throw std::runtime_error(std::string(fn) + ": no value may be negative");
    }
    if (args[2].as_num() > 1.0)
        throw std::runtime_error(std::string(fn) + ": sustain is a level, between 0 and 1");
}

inline double sound_check_hold(const Value* args, int argc, const char* fn) {
    if (argc < 1 || args[0].is_nil())
        return -1.0;   // note TENUE : elle sonnera jusqu'à release()
    if (!args[0].is_number())
        throw std::runtime_error(std::string(fn) + ": duration must be a number of seconds");
    if (args[0].as_num() <= 0.0)
        throw std::runtime_error(std::string(fn) + ": duration must be > 0");
    return args[0].as_num();
}

// Durée d'un tampon, en secondes. La borne haute protège d'une faute de frappe : générer
// dix secondes demande déjà 441 000 appels à la fonction du script, et une durée donnée en
// millisecondes par mégarde figerait le moteur.
inline double sound_check_duration(const Value* args, int argc, int i, const char* fn) {
    if (i >= argc || !args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": duration must be a number of seconds");
    double d = args[i].as_num();
    if (d <= 0.0)
        throw std::runtime_error(std::string(fn) + ": duration must be > 0");
    if (d > k_max_buffer_seconds)
        throw std::runtime_error(std::string(fn) + ": duration exceeds " +
                                 std::to_string((int)k_max_buffer_seconds) + " seconds");
    return d;
}

// Volume et panoramique : bornés en silence, comme le volume général. Un panoramique de
// -1 est à gauche, 0 au centre, 1 à droite (convention de raylib et de p5).
inline double sound_check_unit(const Value* args, int argc, int i, const char* fn, const char* quoi, double mini) {
    if (i >= argc || args[i].is_nil())
        return -2.0;   // absent : l'appelant garde sa valeur courante
    if (!args[i].is_number())
        throw std::runtime_error(std::string(fn) + ": " + quoi + " must be a number");
    double v = args[i].as_num();
    return v < mini ? mini : (v > 1.0 ? 1.0 : v);
}
