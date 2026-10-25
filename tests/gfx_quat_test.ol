## The Quat class of the graphics module: construction, composition, interpolation, inversion and the
## rotation of a vector. It needs the raylib build (the headless one has no `graphics`) but no window,
## so it runs without a display, like tests/gfx_ui_test.ol.

func refusal(f)
    var msg = ""
    try
        f()
    catch e
        msg = e
    end
    return msg
end

func near(a, b)
    return math.abs(a - b) < 0.0001
end

func vec_is(v, x, y, z)
    return near(v[1], x) and near(v[2], y) and near(v[3], z)
end

var identity = graphics.quat()
assert(identity.x == 0 and identity.y == 0 and identity.z == 0 and identity.w == 1)
assert(vec_is(identity.rotateVec(1, 2, 3), 1, 2, 3))

## A quarter turn about Z takes the X axis to the Y axis.
var quarterZ = graphics.quatAxis(0, 0, 1, 90)
assert(vec_is(quarterZ.rotateVec(1, 0, 0), 0, 1, 0))
## A null axis defines no rotation: the identity.
var nothing = graphics.quatAxis(0, 0, 0, 90)
assert(nothing.w == 1 and nothing.x == 0)

## mul applies the right-hand operand first: X turned about Y by 90 degrees, then about Z.
var quarterY = graphics.quatAxis(0, 1, 0, 90)
var both = quarterZ.mul(quarterY)
assert(vec_is(both.rotateVec(1, 0, 0), 0, 0, -1))
var moved = both.rotateVec(1, 2, 3)
var back = both.inverse().rotateVec(moved[1], moved[2], moved[3])
assert(vec_is(back, 1, 2, 3))
assert(quarterZ.mul(quarterZ.inverse()).w > 0.9999)

## Euler angles are in degrees.
var turned = graphics.quatEuler(0, 0, 90).rotateVec(1, 0, 0)
assert(near(turned[1] * turned[1] + turned[2] * turned[2] + turned[3] * turned[3], 1))
assert(vec_is(graphics.quatEuler(90, 0, 0).rotateVec(0, 1, 0), 0, 0, 1))
assert(vec_is(graphics.quatEuler(0, 0, 0).rotateVec(1, 2, 3), 1, 2, 3))

## slerp: halfway between the identity and a quarter turn is an eighth of a turn.
var half = identity.slerp(quarterZ, 0.5)
var eighth = graphics.quatAxis(0, 0, 1, 45)
assert(near(half.z, eighth.z) and near(half.w, eighth.w))
assert(near(identity.slerp(quarterZ, 0).w, 1))
assert(near(identity.slerp(quarterZ, 1).z, quarterZ.z))

## normalize brings a scaled quaternion back to length one; the original is untouched (a Quat is a value).
var scaled = graphics.quat()
scaled.w = 2
var unit = scaled.normalize()
assert(near(unit.w, 1) and scaled.w == 2)

## What each method refuses.
var notQuat = "Quat.mul: expected a Quat (graphics.quat / quatAxis / quatEuler)"
assert(refusal(func() quarterZ.mul({}) end) == notQuat)
assert(refusal(func() quarterZ.mul() end) == "Quat.mul: expected another Quat")
assert(refusal(func() quarterZ.slerp(quarterY) end) == "Quat.slerp: expected a Quat and t")
assert(refusal(func() quarterZ.slerp(5, 0.5) end) == "Quat.slerp: expected a Quat (graphics.quat / quatAxis / quatEuler)")
assert(refusal(func() quarterZ.slerp(quarterY, "x") end) == "Quat.slerp: argument 3 expected number, got string")
assert(refusal(func() quarterZ.rotateVec(1, 2) end) == "Quat.rotateVec: missing argument")
assert(refusal(func() graphics.quatAxis(1, 2) end) == "graphics.quatAxis: missing argument")
assert(refusal(func() graphics.quatEuler(1) end) == "graphics.quatEuler: missing argument")
