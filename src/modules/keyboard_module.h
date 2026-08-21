#pragma once
// Module keyboard — capture clavier pour les applications graphiques.
// Implementation in keyboard_module.cpp, which requires raylib.

// Called once per frame from the render loop (graphics_module.cpp):
// pompe les touches et appelle, si elles existent, keyboard.keypressed(key) /
// keyboard.keyrelease(key) (key = nom de touche).
void keyboard_poll();

// True when keyboard_poll saw at least one press during the current frame. Needed
// parce que la file d'appuis de raylib est CONSOMMÉE par keyboard_poll : la relire
// ailleurs ne rendrait plus rien.
bool keyboard_pressed_any();

// Resets the held-key state. Called at the start of every gfx_run, since s_down is static and
// persists across runs on the shared WASM instance.
void keyboard_reset();
