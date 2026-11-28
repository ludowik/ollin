#pragma once
#include "value.h"
#include <string>
#include <vector>

const std::vector<std::string>& builtin_module_names();
const std::vector<std::string>& builtin_func_names();
Value make_builtin_module(const std::string& name);
// The classes a program names without declaring them (Color, Tween, Camera…), each one with the function that
// builds it: core's members and the globals of every program. A class a build lacks (Camera without a window)
// builds nil and is left out.
struct NativeClass {
    const char* name;
    Value (*make)();
};
const std::vector<NativeClass>& native_classes();
// The 3D classes: graphics3d.cpp and graphics_quat.cpp with a window, graphics_stub.cpp (nil) without.
Value camera_class();
Value light_class();
Value quat_class();
// Forgets what the modules keep from one program to the next: called when a program starts.
void modules_reset();
