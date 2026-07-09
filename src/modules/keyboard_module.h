#pragma once
// Module keyboard — capture clavier pour les applications graphiques.
// Implémentation : keyboard_module.cpp (nécessite raylib).

// Appelé une fois par frame depuis la boucle de rendu (graphics_module.cpp) :
// pompe les touches et appelle, si elles existent, keyboard.keypressed(key) /
// keyboard.keyrelease(key) (key = nom de touche).
void keyboardPoll();

// Réinitialise l'état des touches enfoncées. Appelé au début de chaque gfx_run
// (s_down est statique et persiste entre runs sur l'instance WASM partagée).
void keyboardReset();
