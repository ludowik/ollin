#pragma once
// Module mouse — pointeur (souris / tap tactile) pour les applications graphiques.
// Implémentation : mouse_module.cpp (nécessite raylib).

// Appelé une fois par frame depuis la boucle de rendu (graphics_module.cpp) :
// détecte les actions pointeur et appelle, si elles existent, mouse.pressed(x,y) /
// mouse.released(x,y) / mouse.moved(x,y).
// click_taken : un widget de l'UI a déjà pris ce clic → ne pas appeler pressed/released.
void mouse_poll(bool click_taken = false);
