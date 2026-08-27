#pragma once
// The keyboard module: keyboard capture for graphical programs.
// Implementation in keyboard_module.cpp, which requires raylib.

// Called once per frame from the render loop (graphics_module.cpp):
// pumps the keys and calls keyboard.keypressed(key) and the others when they exist. /
// keyboard.keyrelease(key) (key = a key name).
void keyboard_poll();

// True when keyboard_poll saw at least one press during the current frame. Needed
// because raylib's press queue is CONSUMED by keyboard_poll, so reading it again
// so reading it anywhere else would give nothing.
bool keyboard_pressed_any();

// Resets the held-key state. Called at the start of every gfx_run, since s_down is static and
// persists across runs on the shared WASM instance.
void keyboard_reset();
