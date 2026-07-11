#pragma once
// Classe Quat (rotations par quaternion) — fichier séparé (math pure raymath,
// pas de dépendance rlgl/GL). Utilisée par graphics3d.cpp (graphics.rotateq).
#include "value.h"
#include <raymath.h>

// Construit une instance Quat (classe native) depuis un Quaternion raymath.
Value makeQuatInstance(Quaternion q);
// Relit une instance Quat → Quaternion raymath (lève si ce n'est pas un Quat).
Quaternion quatFromInstance(const Value& v, const char* fn);
// Enregistre les fabriques quat / quat_axis / quat_euler dans le module graphics.
void registerQuat(Value& m);
