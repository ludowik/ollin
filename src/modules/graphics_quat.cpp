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
    // Vérifie que c'est bien une instance Quat (et pas une autre map / un autre
    // objet Camera, Light…) — sinon on fabriquerait un quaternion silencieusement
    // faux (w manquant → 0). On contrôle __class__.__name__ == "Quat".
    Value cls = v.isMap() ? v.mapGet(Value(std::string("__class__"))) : Value{};
    Value name = cls.isClass() ? cls.mapGet(Value(std::string("__name__"))) : Value{};
    if (!(name.isString() && name.asString() == "Quat"))
        throw std::runtime_error(std::string(fn) + ": expected a Quat (graphics.quat / quatAxis / quatEuler)");
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
static Value quat_mul(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion a = quatFromInstance(args[0], "Quat.mul");
    if (argc < 2)
        throw std::runtime_error("Quat.mul: expected another Quat");
    Quaternion b = quatFromInstance(args[1], "Quat.mul");
    return makeQuatInstance(QuaternionMultiply(a, b));
}

// q.slerp(autre, t) : interpolation sphérique (t ∈ [0,1]).
static Value quat_slerp(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion a = quatFromInstance(args[0], "Quat.slerp");
    if (argc < 3)
        throw std::runtime_error("Quat.slerp: expected a Quat and t");
    Quaternion b = quatFromInstance(args[1], "Quat.slerp");
    float t = (float)numArg(args, argc, 2, "Quat.slerp");
    return makeQuatInstance(QuaternionSlerp(a, b, t));
}

// q.normalize() : quaternion normalisé.
static Value quat_normalize(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)argc;
    return makeQuatInstance(QuaternionNormalize(quatFromInstance(args[0], "Quat.normalize")));
}

// q.inverse() : rotation inverse.
static Value quat_inverse(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)argc;
    return makeQuatInstance(QuaternionInvert(quatFromInstance(args[0], "Quat.inverse")));
}

// q.rotateVec(x, y, z) : renvoie le vecteur (x,y,z) tourné par q, sous forme [x,y,z].
static Value quat_rotate_vec(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion q = quatFromInstance(args[0], "Quat.rotateVec");
    Vector3 v = {(float)numArg(args, argc, 1, "Quat.rotateVec"), (float)numArg(args, argc, 2, "Quat.rotateVec"),
                 (float)numArg(args, argc, 3, "Quat.rotateVec")};
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
    cls.mapSet(Value(std::string("rotateVec")), Value::makeBuiltin(quat_rotate_vec));
    return cls;
}

static Value quatClass() {
    static Value cls = makeQuatClass();
    return cls;
}

// ── Fabriques (module graphics) ─────────────────────────────────────────────
// graphics.quat() : quaternion identité (aucune rotation).
static Value gfx_quat(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    return makeQuatInstance(QuaternionIdentity());
}

// graphics.quatAxis(ax, ay, az, deg) : rotation de deg° autour de l'axe (ax,ay,az).
static Value gfx_quat_axis(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 axis = {(float)numArg(args, argc, 0, "graphics.quatAxis"),
                    (float)numArg(args, argc, 1, "graphics.quatAxis"),
                    (float)numArg(args, argc, 2, "graphics.quatAxis")};
    // Axe nul (0,0,0) : aucune rotation définie → identité. Explicite ici plutôt
    // que de dépendre du comportement interne de raymath.
    if (axis.x == 0.0f && axis.y == 0.0f && axis.z == 0.0f)
        return makeQuatInstance(QuaternionIdentity());
    float rad = (float)numArg(args, argc, 3, "graphics.quatAxis") * DEG2RAD;
    return makeQuatInstance(QuaternionFromAxisAngle(axis, rad));
}

// graphics.quatEuler(pitch, yaw, roll) : depuis des angles d'Euler (en degrés).
static Value gfx_quat_euler(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float pitch = (float)numArg(args, argc, 0, "graphics.quatEuler") * DEG2RAD;
    float yaw = (float)numArg(args, argc, 1, "graphics.quatEuler") * DEG2RAD;
    float roll = (float)numArg(args, argc, 2, "graphics.quatEuler") * DEG2RAD;
    return makeQuatInstance(QuaternionFromEuler(pitch, yaw, roll));
}

void registerQuat(Value& m) {
    m.mapSet(Value(std::string("quat")), Value::makeBuiltin(gfx_quat));
    m.mapSet(Value(std::string("quatAxis")), Value::makeBuiltin(gfx_quat_axis));
    m.mapSet(Value(std::string("quatEuler")), Value::makeBuiltin(gfx_quat_euler));
}
