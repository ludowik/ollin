#pragma once
#include "value.h"

// Module `touch` : le MULTITOUCHE — plusieurs doigts suivis en même temps, chacun par un
// identifiant stable.
//
// raylib donne à chaque image une PHOTOGRAPHIE des contacts (combien, où, quels
// identifiants), mais aucun événement : c'est le moteur qui compare la liste de l'image
// courante à celle de la précédente pour en déduire qu'un doigt s'est posé, a bougé ou
// s'est levé. C'est ce suivi qui manquait, et sans lui `mouse` ne peut rapporter qu'un seul
// point — raylib n'émulant la souris que lorsqu'un doigt exactement touche l'écran.
//
// Le script affecte les fonctions qu'il veut, le moteur appelle celles qui existent :
//   touch.began(id, x, y)  un doigt s'est posé
//   touch.moved(id, x, y)  un doigt a bougé
//   touch.ended(id, x, y)  un doigt s'est levé (dernière position connue)
// et peut aussi lire l'état directement : touch.count(), touch.points().
//
// Les rappels de `mouse` ne sont PAS supprimés pour autant : sur un doigt unique, le
// système émule la souris, si bien qu'un script déclarant les deux familles reçoit le geste
// deux fois. À lui de choisir laquelle il écoute.
Value make_touch_module();

// Relève les contacts de l'image. À appeler AVANT tous les autres rappels d'entrée : un
// rappel de `mouse` qui lit `touch.count()` doit voir les doigts de CETTE image.
void touch_begin_frame();

// Compare le relevé à celui de l'image précédente et appelle began/moved/ended.
void touch_poll();

// Au lancement d'un programme : oublie les contacts du précédent, sinon un doigt encore
// « posé » dans la liste ferait croire à un geste en cours.
void touch_reset();
