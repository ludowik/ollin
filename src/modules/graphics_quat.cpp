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

Value quat_class();   // defined below

Quaternion quat_from_instance(const Value& v, const char* fn) {
    // Checks this really is a Quat instance and not some other map (a Camera or a Light object…): a quaternion
    // would be built silently wrong (a missing w reads as 0).
    if (!v.is_instance_of(quat_class()))
        throw std::runtime_error(std::string(fn) + ": expected a Quat (gfx.quat / quatAxis / quatEuler)");
    return Quaternion{(float)quat_field(v, "x"), (float)quat_field(v, "y"), (float)quat_field(v, "z"),
                      (float)quat_field(v, "w")};
}

static void quat_fill(Value& inst, Quaternion q) {
    inst.map_set(Value(std::string("x")), Value((double)q.x));
    inst.map_set(Value(std::string("y")), Value((double)q.y));
    inst.map_set(Value(std::string("z")), Value((double)q.z));
    inst.map_set(Value(std::string("w")), Value((double)q.w));
}

Value make_quat_instance(Quaternion q) {
    Value inst = Value::make_map();
    inst.set_class(quat_class());
    quat_fill(inst, q);
    return inst;
}

// Quat(): the identity, the same as gfx.quat(). A rotation is built by gfx.quatAxis or gfx.quatEuler.
static int quat_init(CallCtx& ctx) {
    if (ctx.argc > 1)
        throw std::runtime_error(
            "Quat: takes no argument, it is the identity (gfx.quatAxis and gfx.quatEuler build a rotation)");
    quat_fill(ctx.args[0], QuaternionIdentity());
    return ctx.ret(Value{});
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

// (ax, ay, az, deg): a rotation of deg degrees about the axis (ax,ay,az).
static Value quat_from_axis(const Value* args, int argc, const char* who) {
    Vector3 axis = {(float)num_arg(args, argc, 0, who), (float)num_arg(args, argc, 1, who),
                    (float)num_arg(args, argc, 2, who)};
    // A null axis (0,0,0) defines no rotation, so we return the identity explicitly rather than
    // depend on raymath's internal behaviour.
    if (axis.x == 0.0f && axis.y == 0.0f && axis.z == 0.0f)
        return make_quat_instance(QuaternionIdentity());
    float rad = (float)num_arg(args, argc, 3, who) * DEG2RAD;
    return make_quat_instance(QuaternionFromAxisAngle(axis, rad));
}

// (pitch, yaw, roll): from Euler angles, in degrees.
static Value quat_from_euler(const Value* args, int argc, const char* who) {
    float pitch = (float)num_arg(args, argc, 0, who) * DEG2RAD;
    float yaw = (float)num_arg(args, argc, 1, who) * DEG2RAD;
    float roll = (float)num_arg(args, argc, 2, who) * DEG2RAD;
    return make_quat_instance(QuaternionFromEuler(pitch, yaw, roll));
}

static int quat_static_axis(CallCtx& ctx);
static int quat_static_euler(CallCtx& ctx);

static Value make_quat_class() {
    return MapBuilder(Value::make_class("Quat"))
        .fn("init", quat_init)
        .fn("mul", quat_mul)
        .fn("slerp", quat_slerp)
        .fn("normalize", quat_normalize)
        .fn("inverse", quat_inverse)
        .fn("rotateVec", quat_rotate_vec)
        .static_fn("axis", quat_static_axis)
        .static_fn("euler", quat_static_euler)
        .done();
}

Value quat_class() {
    static Value cls = make_quat_class();
    return cls;
}

// gfx.quat(): the identity quaternion, no rotation.
static int gfx_quat(CallCtx& ctx) {
    Value* args = ctx.args; int argc = ctx.argc;
    (void)args;
    (void)argc;
    return ctx.ret(make_quat_instance(QuaternionIdentity()));
}

// gfx.quatAxis(...) and Quat.axis(...): the same rotation, named by whoever the script wrote.
static int gfx_quat_axis(CallCtx& ctx) {
    return ctx.ret(quat_from_axis(ctx.args, ctx.argc, "gfx.quatAxis"));
}

// gfx.quatEuler(...) and Quat.euler(...).
static int gfx_quat_euler(CallCtx& ctx) {
    return ctx.ret(quat_from_euler(ctx.args, ctx.argc, "gfx.quatEuler"));
}

static int quat_static_axis(CallCtx& ctx) {
    return ctx.ret(quat_from_axis(ctx.args, ctx.argc, "Quat.axis"));
}

static int quat_static_euler(CallCtx& ctx) {
    return ctx.ret(quat_from_euler(ctx.args, ctx.argc, "Quat.euler"));
}

void register_quat(Value& m) {
    m.map_set(Value(std::string("quat")), Value::make_builtin(gfx_quat));
    m.map_set(Value(std::string("quatAxis")), Value::make_builtin(gfx_quat_axis));
    m.map_set(Value(std::string("quatEuler")), Value::make_builtin(gfx_quat_euler));
}
