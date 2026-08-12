#pragma once
#include "chunk.h"

Value make_tween_module();

// Appelés par la boucle de rendu (graphics_module.cpp, run_user_callbacks) :
// tween_update_all(dt) AVANT update()/draw() — les deux voient donc les valeurs de la
//                      frame courante. Le premier appel marque le module « piloté par le
//                      moteur » et neutralise tween.update côté script (sinon un appel
//                      resté dans draw() doublerait la vitesse).
// tween_reset()        au démarrage d'un PROGRAMME (ollin_run, wasm_main.cpp), comme
//                      ui_reset : les statiques survivent au VM entre deux exécutions du
//                      playground, et les tweens du programme précédent retiendraient ses
//                      objets.
void tween_update_all(double dt);
void tween_reset();
