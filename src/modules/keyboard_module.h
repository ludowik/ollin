#pragma once
// Module keyboard — capture clavier pour les applications graphiques.
// Implémentation : keyboard_module.cpp (nécessite raylib).

// Appelé une fois par frame depuis la boucle de rendu (raylib_module.cpp) :
// pompe les touches et appelle, si elles existent, keyboard.keypressed(key) /
// keyboard.keyrelease(key) (key = nom de touche).
void keyboardPoll();
