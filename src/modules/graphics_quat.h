#pragma once
// The Quat class (quaternion rotations), in its own file since it is pure raymath with no rlgl or
// GL dependency. Used by graphics3d.cpp for graphics.rotateq.
#include "value.h"
#include <raymath.h>

// Builds a Quat instance (the native class) from a raymath Quaternion.
Value make_quat_instance(Quaternion q);
// Reads a Quat instance back as a raymath Quaternion; throws when it is not a Quat.
Quaternion quat_from_instance(const Value& v, const char* fn);
// Registers the quat, quat_axis and quat_euler factories in the graphics module.
void register_quat(Value& m);
