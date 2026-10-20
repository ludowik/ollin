## Regression tests — The motion module and the Tilt steering wheel.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/motion.ol — it must finish without error.

## ── The motion module (orientation, acceleration) ──────────────────────────
## Like touch, the module exists with no sensor — the container has none, and neither has a desktop:
## a script reading it runs and sees zeros instead of failing on a nil. The readings themselves are
## measured in a browser, through the sensor emulation.
assert(typeof(motion) == "module")
assert(motion.state() == "off")
assert(motion.enable() == "unsupported")
assert(motion.state() == "unsupported")
var mRoll, mPitch = motion.tilt()
assert(mRoll == 0 and mPitch == 0)
var mGx, mGy, mGz = motion.gravity()
assert(mGx == 0 and mGy == 0 and mGz == 0)
var mAx, mAy, mAz = motion.acceleration()
assert(mAx == 0 and mAy == 0 and mAz == 0)
assert(motion.attitude() == nil)

## ── The Tilt steering wheel (samples/lib/tilt.ol) ───────────────────────────
## A large dt lets the smoothing settle, so each case reads the steering the roll asks for.
import "../../../docs/samples/lib/tilt.ol"
var tw = Tilt(30, 3)
assert(math.abs(tw.update(10, 2)) < 1e-9)            ## inside the dead zone: straight ahead
assert(math.abs(tw.update(10, 16.5) - 0.5) < 1e-6)   ## halfway between the dead zone and full lock
assert(math.abs(tw.update(10, 100) - 1) < 1e-6)      ## past full lock: clamped
assert(math.abs(tw.update(10, -100) + 1) < 1e-6)     ## the other way round
tw.calibrate(20)
assert(math.abs(tw.update(10, 20)) < 1e-9)           ## the neutral moved with the way the phone is held
assert(math.abs(tw.update(10, 50) - 1) < 1e-6)
tw.reset()                                           ## back to the standard position, a roll of 0
assert(math.abs(tw.update(10, 20) - 17 / 27) < 1e-6)   ## 20 steers again: it was the calibrated neutral
assert(math.abs(tw.update(10, 1)) < 1e-9)
var twSlow = Tilt(30, 3)
var twFirst = twSlow.update(0.01, 100)
assert(twFirst > 0.1 and twFirst < 0.13)             ## one short frame only moves part of the way
## A dead zone of zero is a real value, not a missing one: 0 is falsy, and a default applied with
## `or` would have turned it back into 3.
assert(math.abs(Tilt(30, 0).update(10, 15) - 0.5) < 1e-6)
try
    Tilt(3, 5)
    assert(false)
catch e
    assert(e == "Tilt: fullLock must be larger than deadZone")
end
