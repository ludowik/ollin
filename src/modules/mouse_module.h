#pragma once
// The mouse module: pointer input (mouse, or a touch tap) for graphical programs.
// Implementation in mouse_module.cpp, which requires raylib.

// Called once per frame from the render loop (graphics_module.cpp): detects pointer actions and
// calls mouse.pressed(x,y) and the others when they exist.
// mouse.released(x,y) / mouse.moved(x,y).
// click_taken means a UI widget already took this click, so pressed/released are not called.
void mouse_poll(bool click_taken = false);
// Reset when a program starts (ollin_run), like the other input modules.
void mouse_reset();
