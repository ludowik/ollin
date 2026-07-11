// Classe native Quat — rotations par quaternion (composition sans gimbal-lock +
// interpolation slerp). Math pure raymath (aucune dépendance rlgl/GL) ; compilée
// dans les builds raylib/WASM. Les angles de l'API publique sont en DEGRÉS
// (cohérent avec rotate/rotateX-Y-Z) ; conversion interne en radians pour raymath.
#include "graphics_quat.h"
#include "module_utils.h"
#include "value.h"
#include <raymath.h>
#include <stdexcept>
#include <string>

static double quatField(const Value& v, const char* k) {
    Value f = v.mapGet(Value(std::string(k)));
    return f.isNumber() ? f.asNum() : 0.0;
}

Quaternion quatFromInstance(const Value& v, const char* fn) {
    if (!v.isMap())
        throw std::runtime_error(std::string(fn) + ": expected a Quat (graphics.quat / quat_axis / quat_euler)");
    return Quaternion{(float)quatField(v, "x"), (float)quatField(v, "y"), (float)quatField(v, "z"),
                      (float)quatField(v, "w")};
}

static Value quatClass();   // défini plus bas

Value makeQuatInstance(Quaternion q) {
    Value inst = Value::makeMap();
    inst.mapSet(Value(std::string("__class__")), quatClass());
    inst.mapSet(Value(std::string("x")), Value((double)q.x));
    inst.mapSet(Value(std::string("y")), Value((double)q.y));
    inst.mapSet(Value(std::string("z")), Value((double)q.z));
    inst.mapSet(Value(std::string("w")), Value((double)q.w));
    return inst;
}

// ── Méthodes d'instance (self = args[0]) ────────────────────────────────────
// Un quaternion est une VALEUR : les méthodes renvoient un NOUVEAU Quat (pas de
// mutation), donc chaînables : q.mul(a).normalize().

// q.mul(autre) : composition q · autre (applique d'abord autre, puis q).
static Value quat_mul(Value* args, int argc) {
    Quaternion a = quatFromInstance(args[0], "Quat.mul");
    if (argc < 2)
        throw std::runtime_error("Quat.mul: expected another Quat");
    Quaternion b = quatFromInstance(args[1], "Quat.mul");
    return makeQuatInstance(QuaternionMultiply(a, b));
}

// q.slerp(autre, t) : interpolation sphérique (t ∈ [0,1]).
static Value quat_slerp(Value* args, int argc) {
    Quaternion a = quatFromInstance(args[0], "Quat.slerp");
    if (argc < 3)
        throw std::runtime_error("Quat.slerp: expected a Quat and t");
    Quaternion b = quatFromInstance(args[1], "Quat.slerp");
    float t = (float)numArg(args, argc, 2, "Quat.slerp");
    return makeQuatInstance(QuaternionSlerp(a, b, t));
}

// q.normalize() : quaternion normalisé.
static Value quat_normalize(Value* args, int argc) {
    (void)argc;
    return makeQuatInstance(QuaternionNormalize(quatFromInstance(args[0], "Quat.normalize")));
}

// q.inverse() : rotation inverse.
static Value quat_inverse(Value* args, int argc) {
    (void)argc;
    return makeQuatInstance(QuaternionInvert(quatFromInstance(args[0], "Quat.inverse")));
}

// q.rotate_vec(x, y, z) : renvoie le vecteur (x,y,z) tourné par q, sous forme [x,y,z].
static Value quat_rotate_vec(Value* args, int argc) {
    Quaternion q = quatFromInstance(args[0], "Quat.rotate_vec");
    Vector3 v = {(float)numArg(args, argc, 1, "Quat.rotate_vec"), (float)numArg(args, argc, 2, "Quat.rotate_vec"),
                 (float)numArg(args, argc, 3, "Quat.rotate_vec")};
    Vector3 r = Vector3RotateByQuaternion(v, q);
    Value arr = Value::makeArray();
    arr.arrayPush(Value((double)r.x));
    arr.arrayPush(Value((double)r.y));
    arr.arrayPush(Value((double)r.z));
    return arr;
}

static Value makeQuatClass() {
    Value cls = Value::makeClass();
    cls.mapSet(Value(std::string("__name__")), Value(std::string("Quat")));
    cls.mapSet(Value(std::string("mul")), Value::makeBuiltin(quat_mul));
    cls.mapSet(Value(std::string("slerp")), Value::makeBuiltin(quat_slerp));
    cls.mapSet(Value(std::string("normalize")), Value::makeBuiltin(quat_normalize));
    cls.mapSet(Value(std::string("inverse")), Value::makeBuiltin(quat_inverse));
    cls.mapSet(Value(std::string("rotate_vec")), Value::makeBuiltin(quat_rotate_vec));
    return cls;
}

static Value quatClass() {
    static Value cls = makeQuatClass();
    return cls;
}

// ── Fabriques (module graphics) ─────────────────────────────────────────────
// graphics.quat() : quaternion identité (aucune rotation).
static Value gfx_quat(Value* args, int argc) {
    (void)args;
    (void)argc;
    return makeQuatInstance(QuaternionIdentity());
}

// graphics.quat_axis(ax, ay, az, deg) : rotation de deg° autour de l'axe (ax,ay,az).
static Value gfx_quat_axis(Value* args, int argc) {
    Vector3 axis = {(float)numArg(args, argc, 0, "graphics.quat_axis"),
                    (float)numArg(args, argc, 1, "graphics.quat_axis"),
                    (float)numArg(args, argc, 2, "graphics.quat_axis")};
    float rad = (float)numArg(args, argc, 3, "graphics.quat_axis") * DEG2RAD;
    return makeQuatInstance(QuaternionFromAxisAngle(axis, rad));
}

// graphics.quat_euler(pitch, yaw, roll) : depuis des angles d'Euler (en degrés).
static Value gfx_quat_euler(Value* args, int argc) {
    float pitch = (float)numArg(args, argc, 0, "graphics.quat_euler") * DEG2RAD;
    float yaw = (float)numArg(args, argc, 1, "graphics.quat_euler") * DEG2RAD;
    float roll = (float)numArg(args, argc, 2, "graphics.quat_euler") * DEG2RAD;
    return makeQuatInstance(QuaternionFromEuler(pitch, yaw, roll));
}

void registerQuat(Value& m) {
    m.mapSet(Value(std::string("quat")), Value::makeBuiltin(gfx_quat));
    m.mapSet(Value(std::string("quat_axis")), Value::makeBuiltin(gfx_quat_axis));
    m.mapSet(Value(std::string("quat_euler")), Value::makeBuiltin(gfx_quat_euler));
}
