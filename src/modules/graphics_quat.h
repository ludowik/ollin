#pragma once
// The Quat class (quaternion rotations), in its own file since it is pure raymath with no rlgl or
// GL dependency. Used by graphics3d.cpp for graphics.rotateq.
#include "value.h"
#include <raymath.h>

// Construit une instance Quat (classe native) depuis un Quaternion raymath.
Value make_quat_instance(Quaternion q);
// Reads a Quat instance back as a raymath Quaternion; throws when it is not a Quat.
Quaternion quat_from_instance(const Value& v, const char* fn);
// Enregistre les fabriques quat / quat_axis / quat_euler dans le module graphics.
void register_quat(Value& m);
