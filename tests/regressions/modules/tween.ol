## Regression tests — The tween module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/tween.ol — it must finish without error.

## ── The tween module ───────────────────────────────────────────────────────
## Advancing by EXACT steps (0.25 × 4): a step of 0.1 accumulated ten times does not quite make
## one second in binary, and the tween would not be finished.
tween.cancelAll()
var twObj = {x: 0, n: 0, tint: Color(0, 0, 0)}
var twT = tween.to(twObj, {x: 8}, 1.0, "linear")
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 4 and twT.progress() == 0.5)
tween.update(0.25)
tween.update(0.25)
assert(twObj.x == 8 and twT.isDone() and tween.count() == 0)

## A step longer than the time left stops at the target, with no overshoot.
tween.to(twObj, {x: 5}, 0.5, "linear")
tween.update(10.0)
assert(twObj.x == 5)

## Between two integers the value is NOT rounded: it passes through the fractions, so a field going from 0 to
## 1 can serve as an opacity. Rounding, when wanted, is the script's job.
tween.to(twObj, {n: 10}, 1.0, "linear")
tween.update(0.25)
assert(twObj.n == 2.5)
tween.update(0.75)
## ... but the bounds keep their own type: a field tweened to 10 ends up holding the integer 10 (an array
## index, for one, refuses a float).
assert(twObj.n == 10 and typeof(twObj.n) == "int")

## The bound written back at the START is what the field holds THEN, not what it held when the tween was
## declared: with a delay (the field moved meanwhile) or in the second step of a sequence, a stale one
## put the field back to its old value for a frame.
tween.cancelAll()
var twLate = {x: 0}
tween.to(twLate, {x: 10}, 1.0, "linear").delay(0.5)
twLate.x = 3
tween.update(0.5)
assert(twLate.x == 3)
var twSeq = {x: 0}
tween.sequence(twSeq, [{to: {x: 100}, delay: 1.0, curve: "linear"}, {to: {x: 200}, delay: 1.0, curve: "linear"}])
tween.update(1.0)
assert(twSeq.x == 100)
tween.cancelAll()

## Only the callers that really are at an END write a bound with its own type: a curve that sits ON the
## target midway stays a float until the animation is over.
var twPlateau = {q: 0}
tween.to(twPlateau, {q: 10}, 1.0, func(p) return 1 end)
tween.update(0.5)
assert(twPlateau.q == 10 and typeof(twPlateau.q) == "float")
tween.update(0.5)
assert(twPlateau.q == 10 and typeof(twPlateau.q) == "int")

## An overshooting curve: the final value must be the EXACT target, not 0.99.
var twFini = false
tween.to(twObj, {x: 20}, 0.5, "easeOutBack", func() twFini = true end)
tween.update(0.5)
assert(twObj.x == 20 and twFini)

## Structural interpolation: a class instance animates field by field.
tween.to(twObj, {tint: Color(1, 0.5, 0)}, 1.0, "linear")
tween.update(1.0)
assert(twObj.tint.r == 1 and twObj.tint.g == 0.5 and twObj.tint.b == 0)

## A plain variable by reference, and a curve given as a FUNCTION.
var twVal = 0
tween.value(ref twVal, 100, 1.0, func(p) return p * p end)
tween.update(0.5)
assert(twVal == 25)
tween.update(0.5)
assert(twVal == 100)

## Two tweens on the SAME field: the second cancels the first, which would otherwise fight it and
## make the result depend on the iteration order.
twObj.x = 0
tween.to(twObj, {x: 50}, 1.0, "linear")
tween.to(twObj, {x: -50}, 1.0, "linear")
assert(tween.count() == 1)
tween.update(1.0)
assert(twObj.x == -50)

## Delay: nothing moves before it elapses, and the starting value is the one read AT THE START.
twObj.x = 0
tween.to(twObj, {x: 10}, 1.0, "linear").delay(0.5)
tween.update(0.4)
assert(twObj.x == 0)
twObj.x = 100          ## written during the delay, and that is where the animation starts from
tween.update(0.6)      ## 0.1 s of delay left, then 0.5 s of animation
assert(twObj.x == 55)

## Pause and resume.
twObj.x = 0
var twP = tween.to(twObj, {x: 10}, 1.0, "linear")
tween.update(0.5)
twP.pause()
tween.update(0.5)
assert(twObj.x == 5)
twP.resume()
tween.update(0.5)
assert(twObj.x == 10)

## A completion callback that DECLARES a tween: it push_backs onto the table during the advancing
## pass, so any reference kept across the call would dangle.
var twChain = 0
tween.to(twObj, {x: 0}, 0.5, "linear", func()
    twChain = 1
    tween.to(twObj, {x: 7}, 0.5, "linear", func() twChain = 2 end)
end)
tween.update(0.5)
assert(twChain == 1)
tween.update(0.5)
assert(twChain == 2 and twObj.x == 7)

## A completion callback that CANCELS everything: the pass must not carry on over dead slots.
tween.to(twObj, {x: 1}, 0.5, "linear", func() tween.cancelAll() end)
tween.to(twObj, {n: 1}, 0.5, "linear")
tween.update(0.5)
assert(tween.count() == 0)

## A CURVE supplied by the script may declare further tweens: the table reallocates in the middle
## of the advancing pass, so nothing may hold a reference to an element.
tween.cancelAll()
var twR = {x: 0, y: 0}
var twN = 0
tween.to(twR, {x: 100}, 1.0, func(p)
    twN += 1
    if twN == 1 then
        tween.to(twR, {y: 50}, 1.0, "linear")
    end
    return p
end)
tween.update(0.5)
tween.update(0.5)
## y = 25: the tween born during the first pass is NOT advanced in it — it would consume a time
## step earlier than its birth — so it only gets the second, and the value no longer depends on
## the slot it was given.
assert(twR.x == 100 and twR.y == 25)

## The handle of a finished tween can be queried without error: keeping the handle is normal.
assert(twT.isDone() and twT.progress() == 1)
twT.cancel()

## ── tween: the reading plan (repeat) ───────────────────────────────────────
## `repeat([count] [, roundTrip])`: with no count the repetition is endless; the second parameter
## adds the return trip of the WHOLE. The positions are read every half-second, the animation
## lasting one second, so we read the middle then the end of each pass. In the headless native
## build it is `tween.update` that advances things, the engine not running.
func plWalk(mods, turns)
    var o = {x: 0}
    var t = tween.to(o, {x: 10}, 1.0, "linear")
    mods(t)
    var seen = []
    for i = 1, turns do
        tween.update(0.5)
        seen[#seen + 1] = math.round(o.x)
    end
    return seen
end

## repeat(2): two forward passes. At the end of the first, the position returns to the start.
var plR = plWalk(func(t) t.repeat(2) end, 5)
assert(plR[1] == 5 and plR[2] == 0 and plR[3] == 5 and plR[4] == 10 and plR[5] == 10)

## repeat(2, true): both forward passes, THEN both return ones (+1 +1 -1 -1). Between two return
## passes the position jumps from 0 to 10, just as it jumps from 10 to 0 between two forward ones:
## each segment replays the whole pass in its own direction.
var plRY = plWalk(func(t) t.repeat(2, true) end, 9)
assert(plRY[4] == 10 and plRY[5] == 5 and plRY[6] == 10 and plRY[8] == 0)

## Two calls COMPOSE: the second acts on the plan already built. repeat(nil, true) then repeat(2)
## gives two round trips (+1 -1 +1 -1).
var plYR = plWalk(func(t) t.repeat(nil, true).repeat(2) end, 9)
assert(plYR[2] == 10 and plYR[4] == 0 and plYR[6] == 10 and plYR[8] == 0)

## The bounds are frozen at the first start: writing into the object mid-animation does not
## redefine the start of the next pass, which would otherwise make a return trip drift.
var plO = {x: 0}
var plT = tween.to(plO, {x: 10}, 1.0, "linear").repeat(2)
tween.update(0.5)
plO.x = 100
tween.update(0.5)
assert(plO.x == 0)
plT.cancel()

## `repeat()` with no count is endless. The tween never finishes on its own, and its progress is
## that of the current turn; the `progress` of a finite plan, on the other hand, covers ALL of its
## segments.
var plL = {x: 0}
var plTL = tween.to(plL, {x: 10}, 1.0, "linear").repeat()
tween.update(2.25)
assert(not plTL.isDone() and math.abs(plTL.progress() - 0.25) < 0.001)
plTL.cancel()
var plF = {x: 0}
var plTF = tween.to(plF, {x: 10}, 1.0, "linear").repeat(4)
tween.update(2.0)
assert(math.abs(plTF.progress() - 0.5) < 0.001)
plTF.cancel()

## A stale handle: keeping the handle of a finished animation is normal, so the modifiers must be
## harmless on it.
var plD = {x: 0}
var plTD = tween.to(plD, {x: 1}, 0.1, "linear")
tween.update(0.2)
assert(plTD.isDone())
plTD.repeat(3)
plTD.repeat(nil, true)
plTD.repeat(2, true)
assert(plTD.isDone())

## ── tween.sequence: a run of steps ─────────────────────────────────────────
## The time key is `delay` in both roles: a duration when the step carries `to`, a wait
## otherwise.
var sqO = {x: 0, y: 0}
var sqT = tween.sequence(sqO, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {delay: 0.5},
    {to: {y: 20}, delay: 1.0, curve: "linear"},
])
tween.update(0.5)
assert(sqO.x == 5 and sqO.y == 0)
tween.update(0.5)
assert(sqO.x == 10)
tween.update(0.5)              ## the wait moves nothing
assert(sqO.x == 10 and sqO.y == 0)
tween.update(1.0)
assert(sqO.y == 20 and sqT.isDone())

## A step's starting value is the one the previous step left, not the one the field held when the
## sequence was declared.
var sqE = {v: 0}
tween.sequence(sqE, [
    {to: {v: 100}, delay: 1.0, curve: "linear"},
    {to: {v: 150}, delay: 1.0, curve: "linear"},
])
tween.update(1.0)
tween.update(0.5)
assert(sqE.v == 125)
tween.cancelAll()

## A step can switch object through `target`.
var sqA = {x: 0}
var sqB = {x: 0}
tween.sequence(sqA, [
    {to: {x: 4}, delay: 1.0, curve: "linear"},
    {target: sqB, to: {x: 8}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(sqA.x == 4 and sqB.x == 8)

## `progress` runs over the whole sequence, in TIME: counting the steps crossed would make the
## progress jump, the durations being unequal.
var sqP = {v: 0}
var sqPT = tween.sequence(sqP, [
    {to: {v: 1}, delay: 3.0, curve: "linear"},
    {to: {v: 2}, delay: 1.0, curve: "linear"},
])
tween.update(2.0)
assert(math.abs(sqPT.progress() - 0.5) < 0.001)
sqPT.cancel()

## `repeat` bears on the WHOLE sequence, and the round trip replays it backwards, each step
## reversed. The regression: a time step larger than one step crossed it without reading its
## bounds, and the return trip then set off from a wrong value.
var sqR = {x: 0}
tween.sequence(sqR, [
    {to: {x: 10}, delay: 1.0, curve: "linear"},
    {to: {x: 30}, delay: 1.0, curve: "linear"},
]).repeat(nil, true)
tween.update(2.0)              ## a single step for the whole forward pass
assert(sqR.x == 30)
tween.update(0.5)
assert(sqR.x == 20)            ## the return trip: step 2 replayed from 30 to 10
tween.update(0.5)
assert(sqR.x == 10)
tween.update(1.0)
assert(sqR.x == 0)             ## then step 1, from 10 to 0
tween.cancelAll()

## A wait on its own is a valid sequence, and it does finish.
var sqW = {v: 5}
var sqWT = tween.sequence(sqW, [{delay: 0.5}])
tween.update(0.3)
assert(sqW.v == 5 and not sqWT.isDone())
tween.update(0.3)
assert(sqWT.isDone())

## Overwriting: a tween aiming at the same field cancels the sequence, as it does for tween.to.
var sqX = {x: 0}
tween.sequence(sqX, [{to: {x: 100}, delay: 1.0, curve: "linear"}])
tween.to(sqX, {x: 50}, 1.0, "linear")
tween.update(1.0)
assert(sqX.x == 50 and tween.count() == 0)

## ── tween.curves: the catalogue of the curves, each one usable ──
var twNames = tween.curves()
assert(typeof(twNames) == "array" and len(twNames) > 0)
var twHasLinear = false
for name in twNames do
    assert(typeof(name) == "string", "a curve is named by a string")
    if name == "linear" then
        twHasLinear = true
    end
    ## each name of the catalogue is accepted by a tween, and a finished tween lands exactly on its target
    tween.cancelAll()
    var twCurveObj = {x: 0}
    tween.to(twCurveObj, {x: 10}, 1.0, name)
    tween.update(1.0)
    assert(twCurveObj.x == 10, "the curve {name} ends on the target")
end
assert(twHasLinear)
tween.cancelAll()
