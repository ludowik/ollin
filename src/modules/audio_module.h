#pragma once
#include "value.h"
#include <stdexcept>

// Module `audio` : la SESSION sonore — ouverture du périphérique, volume général, état.
// Un seul par programme, comme le canvas graphique.
//
// Contrairement à `graphics`, ce module n'est JAMAIS nil : un build sans raylib garde
// l'API entière, seule la sortie devient muette (audio_stub.cpp). La raison est que la
// génération d'ondes est un pur calcul, donc testable sans périphérique — et le conteneur
// d'intégration n'en a aucun (`/dev/snd` absent).
Value make_audio_module();

// Points d'accroche, appelés par la boucle de rendu et le démarrage d'un programme :
// audio_wake()   au premier geste de l'utilisateur (clic, touche). Le navigateur refuse de
//                sonner avant une interaction, si bien qu'ouvrir le périphérique au
//                chargement ne servirait à rien ; le moteur le fait donc à ce moment-là et
//                le script n'a rien à écrire.
// audio_update() une fois par frame, après l'ouverture (relance des boucles, entretien).
// audio_reset()  au démarrage d'un PROGRAMME (ollin_run), comme ui_reset : les statiques
//                survivent au VM entre deux exécutions du playground.
void audio_wake();
void audio_update();
void audio_reset();

// Fréquence d'échantillonnage de la sortie, et unité de tous les calculs de synthèse.
// Une constante et non un réglage : la changer invaliderait les tampons déjà calculés.
constexpr int k_audio_sample_rate = 44100;

// ── Validation des arguments, PARTAGÉE par le module et le stub ──────────────────
// Une faute d'appel doit être signalée même sans périphérique (le binaire de test n'en a
// pas) : un seul endroit pour les messages, aucune divergence possible.
inline void audio_check_volume_args(const Value* args, int argc) {
    if (argc >= 1 && !args[0].is_nil() && !args[0].is_number())
        throw std::runtime_error("audio.volume: expected a number between 0 and 1");
}

// Volume borné à [0;1] : au-delà, la sortie sature et le son se déforme au lieu d'être
// plus fort. On corrige en silence plutôt que de refuser, comme les composantes couleur.
inline double audio_clamp_volume(double v) {
    return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}
