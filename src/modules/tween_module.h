#pragma once
#include "chunk.h"

Value make_tween_module();

// Called by the render loop (graphics_module.cpp, run_user_callbacks):
// tween_update_all(dt) BEFORE update() and draw(), so both see this frame's values. The first call
//                      marks the module as engine-driven and turns tween.update into a no-op for
//                      scripts, since a call left in draw() would otherwise double the speed.
// tween_reset()        when a PROGRAM starts (ollin_run, wasm_main.cpp), like ui_reset: the
//                      statics survive the VM between two playground runs, and the previous
//                      program's tweens would keep holding its objects.
void tween_update_all(double dt);
void tween_reset();
