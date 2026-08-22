// The native Quat class: quaternion rotations, composing without gimbal lock, plus
// slerp interpolation). Pure raymath, with no rlgl or GL dependency; compiled
// in the raylib and WASM builds. The public API takes angles in DEGREES
// (consistent with rotate and rotateX/Y/Z), converted internally to radians for raymath.
#include "graphics_quat.h"
#include "module_utils.h"
#include "value.h"
#include <raymath.h>
#include <stdexcept>
#include <string>

static double quat_field(const Value& v, const char* k) {
    Value f = v.map_get(Value(std::string(k)));
    return f.is_number() ? f.as_num() : 0.0;
}

Quaternion quat_from_instance(const Value& v, const char* fn) {
    // Checks this really is a Quat instance and not some other map or other
    // a Camera or Light object…) — otherwise a quaternion would be built silently
    // wrong (a missing w reads as 0), so we check __class__.__name__ == "Quat".
    Value cls = v.is_map() ? v.map_get(Value(std::string("__class__"))) : Value{};
    Value name = cls.is_class() ? cls.map_get(Value(std::string("__name__"))) : Value{};
    if (!(name.is_string() && name.as_string() == "Quat"))
        throw std::runtime_error(std::string(fn) + ": expected a Quat (graphics.quat / quatAxis / quatEuler)");
    return Quaternion{(float)quat_field(v, "x"), (float)quat_field(v, "y"), (float)quat_field(v, "z"),
                      (float)quat_field(v, "w")};
}

static Value quat_class();   // defined below

Value make_quat_instance(Quaternion q) {
    Value inst = Value::make_map();
    inst.map_set(Value(std::string("__class__")), quat_class());
    inst.map_set(Value(std::string("x")), Value((double)q.x));
    inst.map_set(Value(std::string("y")), Value((double)q.y));
    inst.map_set(Value(std::string("z")), Value((double)q.z));
    inst.map_set(Value(std::string("w")), Value((double)q.w));
    return inst;
}

// A quaternion is a VALUE: the methods return a NEW Quat instead of mutating, which makes them
// chainable — q.mul(a).normalize().

// q.mul(other): the composition q times other, applying other first and then q.
static int quat_mul(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion a = quat_from_instance(args[0], "Quat.mul");
    if (argc < 2)
        throw std::runtime_error("Quat.mul: expected another Quat");
    Quaternion b = quat_from_instance(args[1], "Quat.mul");
    return ctx.ret(make_quat_instance(QuaternionMultiply(a, b)));
}

// q.slerp(other, t): spherical interpolation, t in [0,1].
static int quat_slerp(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion a = quat_from_instance(args[0], "Quat.slerp");
    if (argc < 3)
        throw std::runtime_error("Quat.slerp: expected a Quat and t");
    Quaternion b = quat_from_instance(args[1], "Quat.slerp");
    float t = (float)num_arg(args, argc, 2, "Quat.slerp");
    return ctx.ret(make_quat_instance(QuaternionSlerp(a, b, t)));
}

static int quat_normalize(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)argc;
    return ctx.ret(make_quat_instance(QuaternionNormalize(quat_from_instance(args[0], "Quat.normalize"))));
}

// q.inverse() : rotation inverse.
static int quat_inverse(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)argc;
    return ctx.ret(make_quat_instance(QuaternionInvert(quat_from_instance(args[0], "Quat.inverse"))));
}

// q.rotateVec(x, y, z): the vector (x,y,z) rotated by q, returned as [x,y,z].
static int quat_rotate_vec(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Quaternion q = quat_from_instance(args[0], "Quat.rotateVec");
    Vector3 v = {(float)num_arg(args, argc, 1, "Quat.rotateVec"), (float)num_arg(args, argc, 2, "Quat.rotateVec"),
                 (float)num_arg(args, argc, 3, "Quat.rotateVec")};
    Vector3 r = Vector3RotateByQuaternion(v, q);
    Value arr = Value::make_array();
    arr.array_push(Value((double)r.x));
    arr.array_push(Value((double)r.y));
    arr.array_push(Value((double)r.z));
    return ctx.ret(arr);
}

static Value make_quat_class() {
    Value cls = Value::make_class();
    cls.map_set(Value(std::string("__name__")), Value(std::string("Quat")));
    cls.map_set(Value(std::string("mul")), Value::make_builtin(quat_mul));
    cls.map_set(Value(std::string("slerp")), Value::make_builtin(quat_slerp));
    cls.map_set(Value(std::string("normalize")), Value::make_builtin(quat_normalize));
    cls.map_set(Value(std::string("inverse")), Value::make_builtin(quat_inverse));
    cls.map_set(Value(std::string("rotateVec")), Value::make_builtin(quat_rotate_vec));
    return cls;
}

static Value quat_class() {
    static Value cls = make_quat_class();
    return cls;
}

// graphics.quat(): the identity quaternion, no rotation.
static int gfx_quat(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    return ctx.ret(make_quat_instance(QuaternionIdentity()));
}

// graphics.quatAxis(ax, ay, az, deg): a rotation of deg degrees about the axis (ax,ay,az).
static int gfx_quat_axis(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    Vector3 axis = {(float)num_arg(args, argc, 0, "graphics.quatAxis"),
                    (float)num_arg(args, argc, 1, "graphics.quatAxis"),
                    (float)num_arg(args, argc, 2, "graphics.quatAxis")};
    // A null axis (0,0,0) defines no rotation, so we return the identity explicitly rather than
    // depend on raymath's internal behaviour.
    if (axis.x == 0.0f && axis.y == 0.0f && axis.z == 0.0f)
        return ctx.ret(make_quat_instance(QuaternionIdentity()));
    float rad = (float)num_arg(args, argc, 3, "graphics.quatAxis") * DEG2RAD;
    return ctx.ret(make_quat_instance(QuaternionFromAxisAngle(axis, rad)));
}

// graphics.quatEuler(pitch, yaw, roll): from Euler angles, in degrees.
static int gfx_quat_euler(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    float pitch = (float)num_arg(args, argc, 0, "graphics.quatEuler") * DEG2RAD;
    float yaw = (float)num_arg(args, argc, 1, "graphics.quatEuler") * DEG2RAD;
    float roll = (float)num_arg(args, argc, 2, "graphics.quatEuler") * DEG2RAD;
    return ctx.ret(make_quat_instance(QuaternionFromEuler(pitch, yaw, roll)));
}

void register_quat(Value& m) {
    m.map_set(Value(std::string("quat")), Value::make_builtin(gfx_quat));
    m.map_set(Value(std::string("quatAxis")), Value::make_builtin(gfx_quat_axis));
    m.map_set(Value(std::string("quatEuler")), Value::make_builtin(gfx_quat_euler));
}
