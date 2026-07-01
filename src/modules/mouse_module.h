#pragma once
// Module mouse — pointeur (souris / tap tactile) pour les applications graphiques.
// Implémentation : mouse_module.cpp (nécessite raylib).

// Appelé une fois par frame depuis la boucle de rendu (raylib_module.cpp) :
// détecte les actions pointeur et appelle, si elles existent, mouse.pressed(x,y) /
// mouse.released(x,y) / mouse.moved(x,y).
void mousePoll();
