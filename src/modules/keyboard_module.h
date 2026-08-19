#pragma once
// Module keyboard — capture clavier pour les applications graphiques.
// Implémentation : keyboard_module.cpp (nécessite raylib).

// Appelé une fois par frame depuis la boucle de rendu (graphics_module.cpp) :
// pompe les touches et appelle, si elles existent, keyboard.keypressed(key) /
// keyboard.keyrelease(key) (key = nom de touche).
void keyboard_poll();

// Vrai si keyboard_poll a vu au moins un appui pendant la frame courante. Nécessaire
// parce que la file d'appuis de raylib est CONSOMMÉE par keyboard_poll : la relire
// ailleurs ne rendrait plus rien.
bool keyboard_pressed_any();

// Réinitialise l'état des touches enfoncées. Appelé au début de chaque gfx_run
// (s_down est statique et persiste entre runs sur l'instance WASM partagée).
void keyboard_reset();
